import SwiftUI

// MARK: - Carbon Theme (IBM Carbon Design System, Gray 100)

/// IBM Carbon's White / Gray 10 theme: flat layers, square corners, 1-px structural borders,
/// Blue 60 for primary actions and accents.
public struct CarbonTheme: DashboardTheme {
    public let id: ThemeType = .carbon

    private static let blue60 = Color(red: 0.06, green: 0.38, blue: 1.00)   // #0f62fe

    public let colors = ThemeColors(
        background: Color(red: 0.96, green: 0.96, blue: 0.96),       // Gray 10 #f4f4f4
        panelBackground: Color.white,                                 // White #ffffff
        foreground: Color(red: 0.09, green: 0.09, blue: 0.09),       // Gray 100 #161616
        border: Color(red: 0.78, green: 0.78, blue: 0.78),           // Gray 30 #c6c6c6
        accent: CarbonTheme.blue60
    )

    /// IBM Plex Sans if installed; otherwise the system font.
    public let fontName = "IBMPlexSans"

    public var barColor: Color { CarbonTheme.blue60 }

    public func applyPanelStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(16)
                .background(colors.panelBackground)
                .overlay(Rectangle().strokeBorder(colors.border, lineWidth: 1))
        )
    }

    public func applyButtonStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundColor(.white)
                .background(CarbonTheme.blue60)
        )
    }
}
