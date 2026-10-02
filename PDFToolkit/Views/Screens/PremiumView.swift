import Foundation
import SwiftUI

private enum PremiumPlan: String, CaseIterable, Identifiable {
    case weekly, monthly, yearly, lifetime
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Weekly plan"
        case .monthly: return "Monthly plan"
        case .yearly: return "Yearly plan"
        case .lifetime: return "Life Time"
        }
    }

    var badge: String {
        switch self {
        case .weekly: return "Basic"
        case .monthly: return "3 Days Free Trial"
        case .yearly: return "88% OFF"
        case .lifetime: return "50% OFF"
        }
    }

    var productID: String {
        switch self {
        case .weekly: return AppConfig.weeklyProductID
        case .monthly: return AppConfig.monthlyProductID
        case .yearly: return AppConfig.yearlyProductID
        case .lifetime: return AppConfig.lifetimeProductID
        }
    }
}

struct PremiumView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var entitlements: EntitlementManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedPlan: PremiumPlan = .monthly
    @State private var isPurchasing = false
    @State private var showingPrivacy = false
    @State private var showingTerms = false

    var body: some View {
        premiumPanel
            .frame(width: 820, height: 600)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.18), radius: 26, y: 14)
            .task {
                if entitlements.products.isEmpty && !entitlements.isLoadingProducts {
                    await entitlements.loadProducts()
                }
            }
            .onExitCommand { appState.dismissPremium() }
            .alert("Purchase", isPresented: errorAlertPresented) {
                Button("OK", role: .cancel) { entitlements.lastErrorMessage = nil }
            } message: {
                Text(entitlements.lastErrorMessage ?? "")
            }
            .sheet(isPresented: $showingPrivacy) {
                LegalTextView(title: "Privacy Policy", bodyText: privacyText)
            }
            .sheet(isPresented: $showingTerms) {
                LegalTextView(title: "Terms of Use", bodyText: termsText)
            }
    }

    private var premiumPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(panelBackground)

            decorativeBackground

            VStack(spacing: 0) {
                titleRow
                    .padding(.top, 31)

                featureRow
                    .padding(.top, 24)

                planContainer
                    .padding(.horizontal, 58)
                    .padding(.top, 28)

                Button(action: purchaseSelectedPlan) {
                    HStack(spacing: 8) {
                        if isPurchasing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text("Continue")
                            .font(.system(size: 22, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 314, height: 58)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.42, blue: 0.96), Color(red: 0.12, green: 0.30, blue: 0.89)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: AppTheme.blue.opacity(0.30), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || entitlements.product(for: selectedPlan.productID) == nil)
                .padding(.top, 17)

                Text(footerLine)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.top, 8)

                Text("Payment will be charged to your Apple ID account at confirmation of purchase. Auto-renewable subscriptions renew unless cancelled at least 24 hours before the end of the current period.")
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 655)
                    .padding(.top, 14)

                HStack(spacing: 52) {
                    Button("Privacy Policy") { showingPrivacy = true }
                    Button("Restore Purchase") { Task { await entitlements.restorePurchases() } }
                    Button("Terms of Use") { showingTerms = true }
                    Button("Continue With Free Plan") { appState.dismissPremium() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                .padding(.top, 10)
                .padding(.bottom, 15)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.50), lineWidth: 1)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 13) {
            Text("Unlock All Features")
                .font(.system(size: 35, weight: .bold))
                .foregroundStyle(AppTheme.text)

            Image(systemName: "printer.fill")
                .font(.system(size: 31))
                .symbolRenderingMode(.palette)
                .foregroundStyle(AppTheme.text, Color.yellow)
        }
    }

    private var featureRow: some View {
        HStack(spacing: 30) {
            premiumFeature("Unlimited Files Usage")
            premiumFeature("All PDF Tools")
            premiumFeature("200MB Pro Files")
        }
    }

    private var planContainer: some View {
        HStack(spacing: 15) {
            ForEach(PremiumPlan.allCases) { plan in
                planCard(plan)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(planWellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.47, green: 0.64, blue: 1.0), lineWidth: 4)
        }
        .shadow(color: Color(red: 0.30, green: 0.49, blue: 0.95).opacity(0.12), radius: 8, y: 3)
    }

    private func planCard(_ plan: PremiumPlan) -> some View {
        let selected = selectedPlan == plan
        let price = entitlements.displayPrice(for: plan.productID) ?? "—"

        return Button {
            selectedPlan = plan
        } label: {
            VStack(spacing: 0) {
                Text(plan.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.text)
                    .padding(.top, 20)

                Spacer()

                Text(price)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.text)

                Text(plan.badge)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(selected && plan == .monthly ? Color.white : AppTheme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(selected && plan == .monthly ? AppTheme.blue : Color.clear)
                    .clipShape(Capsule())
                    .overlay {
                        if !(selected && plan == .monthly) {
                            Capsule().stroke(AppTheme.line.opacity(0.85), lineWidth: 1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .padding(.top, 17)
            }
            .frame(width: 142, height: 194)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(selected ? AppTheme.blue : AppTheme.line.opacity(0.45), lineWidth: selected ? 3 : 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func premiumFeature(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.67, green: 0.84, blue: 0.56))
                .frame(width: 19, height: 19)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.18, green: 0.36, blue: 0.18))
                }

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.text)
        }
    }

    private var decorativeBackground: some View {
        ZStack {
            PremiumStarburst()
                .stroke(AppTheme.muted.opacity(0.16), lineWidth: 2)
                .frame(width: 56, height: 56)
                .offset(x: -344, y: -224)

            PremiumStarburst()
                .stroke(AppTheme.muted.opacity(0.10), lineWidth: 2)
                .frame(width: 56, height: 56)
                .offset(x: 335, y: 225)

            PremiumStarburst()
                .fill(Color(red: 0.38, green: 0.57, blue: 1.0))
                .frame(width: 20, height: 20)
                .offset(x: 346, y: -154)

            PremiumStarburst()
                .fill(Color(red: 0.38, green: 0.57, blue: 1.0))
                .frame(width: 19, height: 19)
                .offset(x: -350, y: 214)

            Circle()
                .stroke(AppTheme.muted.opacity(0.10), lineWidth: 6)
                .frame(width: 650, height: 430)
                .offset(x: -278, y: 183)

            Circle()
                .stroke(AppTheme.muted.opacity(0.08), lineWidth: 5)
                .frame(width: 430, height: 430)
                .offset(x: 430, y: -145)
        }
        .allowsHitTesting(false)
    }

    private var panelBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.15)
            : Color(red: 0.985, green: 0.99, blue: 1.0)
    }

    private var planWellBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.20, blue: 0.29)
            : Color(red: 0.88, green: 0.93, blue: 1.0)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.16)
            : Color.white
    }

    private var footerLine: String {
        let price = entitlements.displayPrice(for: selectedPlan.productID) ?? "—"
        switch selectedPlan {
        case .monthly: return "3 Days Free Trial, then \(price) per month"
        case .weekly: return "\(price) per week"
        case .yearly: return "\(price) per year"
        case .lifetime: return "\(price) one-time purchase"
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { entitlements.lastErrorMessage != nil },
            set: { if !$0 { entitlements.lastErrorMessage = nil } }
        )
    }

    private func purchaseSelectedPlan() {
        if AppConfig.testingEntitlementOverride == .forcePro {
            appState.completeUpgrade()
            return
        }

        if entitlements.isPro {
            appState.completeUpgrade()
            return
        }

        isPurchasing = true
        Task {
            let success = await entitlements.purchase(productID: selectedPlan.productID)
            isPurchasing = false
            if success {
                appState.completeUpgrade()
            }
        }
    }

    private var privacyText: String {
        "PDF Toolkit processes implemented PDF operations locally in this build. Temporary processing files are removed when workflows are cleared or the app exits normally. History stores a small local thumbnail and a bookmark to files the user explicitly saved; it does not duplicate full documents or store PDF passwords. If server features are added later, this policy must be updated before release."
    }

    private var termsText: String {
        "Subscriptions and purchases are handled by Apple StoreKit. Weekly, monthly and yearly plans are intended as auto-renewable subscriptions; the lifetime plan is intended as a non-consumable purchase. Production pricing, storefront currency, trial eligibility, taxes and renewal behavior are controlled by App Store Connect and Apple's purchase sheet. Users must only unlock PDFs they are authorized to access."
    }
}

private struct PremiumStarburst: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.5
        let inner = outer * 0.24
        let points = 16
        var path = Path()

        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -Double.pi / 2 + Double(index) * Double.pi / Double(points)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct LegalTextView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            ScrollView {
                Text(bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(width: 560, height: 360)
    }
}
