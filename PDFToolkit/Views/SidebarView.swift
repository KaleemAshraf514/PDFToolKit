import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var entitlements: EntitlementManager

    private var selected: AppDestination { appState.destination }

    var body: some View {
        VStack(spacing: 0) {
            brand

            SidebarButton(title: "Home", systemImage: "house", isSelected: isHome) {
                appState.destination = .home
            }
            SidebarButton(title: "History", systemImage: "clock.arrow.circlepath", isSelected: isHistory) {
                appState.destination = .history
            }
            SidebarButton(title: "Tools", systemImage: "square.grid.3x3", isSelected: isTools) {
                appState.destination = .tools
            }

            if !entitlements.isPro {
                Divider().padding(.vertical, 8)

                SidebarButton(
                    title: "Upgrade to PRO",
                    systemImage: "crown",
                    isSelected: appState.isPremiumPresented
                ) {
                    appState.presentPremium()
                }

                SidebarButton(title: "Restore Purchase", systemImage: "bag.badge.plus", isSelected: false) {
                    Task { await entitlements.restorePurchases() }
                }
            }

            Spacer(minLength: 20)

            if !entitlements.isPro {
                bottomUpgradeButton
            }

            Text("App Version - V\(AppConfig.appVersion)")
                .font(.system(size: 8))
                .foregroundStyle(AppTheme.tertiaryText)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .frame(width: AppTheme.sidebarWidth)
        .background(AppTheme.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.line).frame(width: 1)
        }
    }

    private var brand: some View {
        VStack(spacing: 7) {
            Image(systemName: "printer.fill")
                .font(.system(size: 31))
                .symbolRenderingMode(.palette)
                .foregroundStyle(AppTheme.text, Color.yellow)
                .padding(.top, 23)
            Text(AppConfig.appName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    private var bottomUpgradeButton: some View {
        Button {
            appState.presentPremium()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "medal.star")
                    .font(.system(size: 16))
                Text("Upgrade to Pro")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(AppTheme.blue)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var isHome: Bool {
        if case .home = selected { return true }
        return false
    }

    private var isHistory: Bool {
        if case .history = selected { return true }
        return false
    }

    private var isTools: Bool {
        switch selected {
        case .tools, .tool: return true
        default: return false
        }
    }
}
