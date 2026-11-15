import SwiftUI

// MARK: - Slate UI Theme

/// Cool slate neutrals with soft rounded panels, hairline borders, a gentle drop shadow
/// and a sky-blue accent.
public struct SlateTheme: DashboardTheme {
    public let id: ThemeType = .slate

    private static let sky = Color(red: 0.22, green: 0.74, blue: 0.97)      // sky-400 #38bdf8
    private static let slate900 = Color(red: 0.06, green: 0.09, blue: 0.16) // slate-900 #0f172a

    public let colors = ThemeColors(
        background: SlateTheme.slate900,
        panelBackground: Color(red: 0.12, green: 0.16, blue: 0.23),  // slate-800 #1e293b
        foreground: Color(red: 0.89, green: 0.91, blue: 0.94),       // slate-200 #e2e8f0
        border: Color(red: 0.20, green: 0.25, blue: 0.33),           // slate-700 #334155
        accent: SlateTheme.sky
    )

    /// System font (SF).
    public let fontName = ""

    public var barColor: Color { SlateTheme.sky }

    public func applyPanelStyle(to view: AnyView) -> AnyView {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return AnyView(
            view
                .padding(14)
                .background(shape.fill(colors.panelBackground))
                .overlay(shape.strokeBorder(colors.border, lineWidth: 1))
                .compositingGroup()
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 2)
        )
    }

    public func applyButtonStyle(to view: AnyView) -> AnyView {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return AnyView(
            view
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .foregroundColor(SlateTheme.slate900)
                .background(shape.fill(SlateTheme.sky))
        )
    }
}
