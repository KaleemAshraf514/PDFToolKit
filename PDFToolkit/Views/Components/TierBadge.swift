import SwiftUI

struct TierBadge: View {
    let tier: ToolTier

    var body: some View {
        Text(tier.rawValue)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tier == .free ? AppTheme.success : AppTheme.blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((tier == .free ? AppTheme.success : AppTheme.blue).opacity(0.10))
            .clipShape(Capsule())
    }
}
