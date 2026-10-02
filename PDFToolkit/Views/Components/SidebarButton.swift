import SwiftUI

struct SidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 11))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppTheme.text : AppTheme.muted)
            .padding(.horizontal, 18)
            .frame(width: AppTheme.sidebarWidth, height: 42, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: AppTheme.sidebarWidth, height: 42)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return AppTheme.sidebarSelection }
        if isHovering { return AppTheme.sidebarSelection.opacity(0.55) }
        return .clear
    }
}
