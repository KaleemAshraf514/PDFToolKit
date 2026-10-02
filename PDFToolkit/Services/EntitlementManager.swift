import AppKit
import Foundation
import StoreKit

/// Central StoreKit 2 source of truth for product metadata, purchases and Pro entitlement.
///
/// With no `.storekit` configuration attached to the Run scheme, `Product.products(for:)`
/// resolves these IDs against App Store Connect (Sandbox/TestFlight/App Store depending on
/// how the app is signed and launched). Only verified StoreKit transactions grant Pro.
@MainActor
final class EntitlementManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    @Published var lastErrorMessage: String?

    private var transactionListener: Task<Void, Never>?
    private var appActivationListener: Task<Void, Never>?
    private var storefrontListener: Task<Void, Never>?

    var storeEntitledToPro: Bool {
        !activeProductIDs.isEmpty
    }

    var isPro: Bool {
        switch AppConfig.testingEntitlementOverride {
        case .forcePro:
            return true
        case .forceFree:
            return false
        case .normal:
            return storeEntitledToPro
        }
    }

    var planLabel: String {
        isPro ? "PRO" : "FREE"
    }

    init() {
        transactionListener = listenForTransactions()
        appActivationListener = listenForAppActivation()
        storefrontListener = listenForStorefrontChanges()

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionListener?.cancel()
        appActivationListener?.cancel()
        storefrontListener?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: AppConfig.productIDs)
            products = loaded.sorted { lhs, rhs in
                order(for: lhs.id) < order(for: rhs.id)
            }

            let loadedIDs = Set(loaded.map(\.id))
            let missingIDs = AppConfig.productIDs.subtracting(loadedIDs)
            if !missingIDs.isEmpty {
                lastErrorMessage = "App Store did not return: \(missingIDs.sorted().joined(separator: ", ")). Check App Store Connect product IDs, availability, agreements, signing team, and Sandbox account."
            }
        } catch {
            products = []
            lastErrorMessage = "Unable to load App Store products: \(error.localizedDescription)"
        }
    }

    func product(for id: String) -> Product? {
        products.first(where: { $0.id == id })
    }

    /// StoreKit/App Store is the only price source. No hard-coded or local StoreKit price
    /// is used in the purchase UI.
    func displayPrice(for productID: String) -> String? {
        product(for: productID)?.displayPrice
    }

    func purchase(productID: String) async -> Bool {
        guard let product = product(for: productID) else {
            lastErrorMessage = "This product is not available from the App Store right now. Check App Store Connect and your Sandbox/App Store account, then try again."
            return false
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                let transaction = try verified(verificationResult)
                guard AppConfig.productIDs.contains(transaction.productID) else {
                    lastErrorMessage = "The App Store returned an unexpected product."
                    return false
                }

                // A verified successful purchase is enough to grant access immediately.
                // Do not wait for currentEntitlements to propagate before updating the UI;
                // Sandbox can lag briefly after PurchaseResult.success.
                activeProductIDs.insert(transaction.productID)
                await transaction.finish()

                // Reconcile with the App Store shortly afterwards. This catches revocations,
                // expirations and account/storefront changes without delaying the UI transition.
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(750))
                    await self?.refreshEntitlements()
                }

                return true

            case .pending:
                lastErrorMessage = "Purchase is pending approval."
                return false

            case .userCancelled:
                return false

            @unknown default:
                lastErrorMessage = "StoreKit returned an unknown purchase result."
                return false
            }
        } catch {
            lastErrorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var current: Set<String> = []

        for await result in StoreKit.Transaction.currentEntitlements {
            do {
                let transaction = try verified(result)
                guard AppConfig.productIDs.contains(transaction.productID) else { continue }
                guard transaction.revocationDate == nil else { continue }
                guard !transaction.isUpgraded else { continue }
                if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                    continue
                }
                current.insert(transaction.productID)
            } catch {
                // Unverified transactions must never unlock paid features.
                continue
            }
        }

        activeProductIDs = current
    }

    func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        NSWorkspace.shared.open(url)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.verified(result)
                    guard AppConfig.productIDs.contains(transaction.productID) else {
                        await transaction.finish()
                        continue
                    }
                    await transaction.finish()
                    await self.refreshEntitlements()
                } catch {
                    continue
                }
            }
        }
    }


    /// Re-check entitlements whenever the user returns to the app. This is important
    /// during Sandbox testing because signing in/out happens in App Store settings.
    private func listenForAppActivation() -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                guard let self else { return }
                await self.refreshEntitlements()
            }
        }
    }

    /// A storefront change can accompany Sandbox account/storefront changes. Reload
    /// product metadata and reconcile entitlements when StoreKit reports one.
    private func listenForStorefrontChanges() -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in Storefront.updates {
                guard let self else { return }
                await self.loadProducts()
                await self.refreshEntitlements()
            }
        }
    }

    nonisolated private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    private func order(for id: String) -> Int {
        switch id {
        case AppConfig.weeklyProductID: return 0
        case AppConfig.monthlyProductID: return 1
        case AppConfig.yearlyProductID: return 2
        case AppConfig.lifetimeProductID: return 3
        default: return 99
        }
    }
}
