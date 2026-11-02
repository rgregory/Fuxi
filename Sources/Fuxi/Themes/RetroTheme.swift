import SwiftUI

// MARK: - Retro Theme

/// Off-white window, white panels with a 2-px black border and a hard black drop shadow,
/// square corners, strict monochrome.
public struct RetroTheme: DashboardTheme {
    public let id: ThemeType = .retro

    public let colors = ThemeColors(
        background: Color(red: 0.95, green: 0.95, blue: 0.95),
        panelBackground: Color.white,
        foreground: Color.black,
        border: Color.black,
        accent: Color.black
    )

    /// Chicago if a copy is installed; otherwise Geneva.
    public let fontName = "Chicago"

    public func applyPanelStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(12)
                .background(colors.panelBackground)
                .border(colors.border, width: 2)
                // Flatten first so the shadow follows the box, not each letter.
                .compositingGroup()
                .shadow(color: colors.border, radius: 0, x: 3, y: 3)
        )
    }

    public func applyButtonStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .foregroundColor(colors.foreground)
                .background(RoundedRectangle(cornerRadius: 5).fill(colors.panelBackground))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(colors.border, lineWidth: 2))
                .compositingGroup()
                .shadow(color: colors.border, radius: 0, x: 2, y: 2)
        )
    }
}
