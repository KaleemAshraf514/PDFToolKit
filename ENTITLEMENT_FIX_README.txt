PDF Toolkit v15 - StoreKit entitlement UI fix

Changed file:
PDFToolkit/Services/EntitlementManager.swift

What changed:
1. A verified Product.purchase() success now inserts the purchased product into activeProductIDs immediately, so SwiftUI updates at once and the Premium modal can close without waiting for currentEntitlements propagation.
2. Entitlements are reconciled again shortly after purchase.
3. The app re-checks Transaction.currentEntitlements whenever the app becomes active (important after switching to App Store settings during Sandbox testing).
4. Storefront changes reload products and re-check entitlements.
5. Expired subscription transactions are explicitly ignored.

Important Sandbox behavior:
Signing out of the Sandbox Apple Account is not itself a StoreKit revocation event. If StoreKit still reports the purchase in Transaction.currentEntitlements, the app must continue to consider it owned. To reset a Sandbox purchase, use Clear Purchase History (or a fresh sandbox account) and then sign out/in as Apple documents.
