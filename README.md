# PDF Toolkit macOS — v14

Native SwiftUI macOS project (AppKit/PDFKit only where needed for native canvas/PDF behavior).

## StoreKit / App Store Connect
- Bundle identifier: `com.nt.testapp`
- Weekly: `com.nt.weekly`
- Monthly: `com.nt.monthly`
- Yearly: `com.nt.yearly`
- Lifetime non-consumable: `com.nt.lifetime`
- No local `.storekit` configuration is bundled or attached to the Run scheme.
- Product prices come only from StoreKit `Product.displayPrice`.
- Purchases use StoreKit 2 `Product.purchase()` and verified transactions.
- Pro entitlement comes from verified `Transaction.currentEntitlements` (or the explicit development override in `AppConfig.swift`).

To use App Store Connect/Sandbox products, select the Apple Developer Team that owns `com.nt.testapp` in Signing & Capabilities and ensure all four product IDs exist in App Store Connect.

## Development entitlement override
`PDFToolkit/Core/AppConfig.swift`
- `.normal` (default in this build): real verified StoreKit entitlement
- `.forcePro`: development-only forced Pro
- `.forceFree`: development-only forced Free

## Navigation behavior
The sidebar is shown only on Home, History, and Tools. Tool workflows and the PDF editor/canvas use the full window and expose their own Back action. Returning to a top-level screen restores the sidebar.

## Pro UI behavior
When Pro is active, Upgrade/Restore/Manage purchase UI is removed from the sidebar and Pro crown tags are hidden from tool cards. In Free mode, Upgrade/Restore and Pro tags are shown.

## Open
Open `PDFToolkit.xcodeproj` (or `PDFToolkit.xcworkspace`).
