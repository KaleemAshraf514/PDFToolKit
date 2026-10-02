import Foundation

/// A single testing switch for entitlement simulation.
///
/// Change `testingEntitlementOverride` to:
/// - `.forcePro`  -> unlocks every paid feature while developing/testing.
/// - `.forceFree` -> forces the free plan to test paywalls.
/// - `.normal`    -> uses verified StoreKit entitlements.
///
/// This is intentionally centralized so no individual screen hardcodes premium state.
enum TestingEntitlementOverride: String {
    case normal
    case forcePro
    case forceFree
}

enum AppConfig {
    static let appName = "PDF Toolkit"
    static let appVersion = "1.0.0"

    // MARK: Testing key requested for development
    static let testingEntitlementOverride: TestingEntitlementOverride = .normal

    // MARK: Product identifiers
    static let weeklyProductID = "com.nt.weekly"
    static let monthlyProductID = "com.nt.monthly"
    static let yearlyProductID = "com.nt.yearly"
    static let lifetimeProductID = "com.nt.lifetime"

    static let productIDs: Set<String> = [
        weeklyProductID,
        monthlyProductID,
        yearlyProductID,
        lifetimeProductID
    ]

    static let freeFileLimitBytes: Int64 = 10 * 1024 * 1024
    static let proFileLimitBytes: Int64 = 200 * 1024 * 1024

    /// Metadata only. Documents/passwords are never persisted here.
    static let historyLimit = 100
}
