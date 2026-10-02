import AppKit
import SwiftUI

/// Shared visual tokens. The layout follows the supplied Figma reference while
/// semantic system colours keep it correct in both macOS Light and Dark modes.
enum AppTheme {
    static let blue = Color(red: 0.18, green: 0.36, blue: 0.93)
    static let nsBlue = NSColor(srgbRed: 0.18, green: 0.36, blue: 0.93, alpha: 1)
    static let blueHover = Color(red: 0.14, green: 0.30, blue: 0.84)

    static let text = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let line = Color(nsColor: .separatorColor)

    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevatedSurface = Color(nsColor: .textBackgroundColor)
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarSelection = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let canvasBackground = Color(nsColor: .underPageBackgroundColor)

    static let success = Color(red: 0.11, green: 0.62, blue: 0.33)
    static let warning = Color(red: 0.96, green: 0.56, blue: 0.08)
    static let danger = Color(red: 0.90, green: 0.20, blue: 0.25)

    static let sidebarWidth: CGFloat = 184
    static let inspectorWidth: CGFloat = 238
    static let cornerRadius: CGFloat = 10

    static func softCardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)
    }

    static func premiumPanelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.white
    }

    static func premiumCardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.16) : Color.white
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 9) -> some View {
        self
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
    }
}
