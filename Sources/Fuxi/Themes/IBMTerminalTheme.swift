import SwiftUI

// MARK: - IBM Corporate Terminal Theme

public struct IBMTerminalTheme: DashboardTheme {
    public let id: ThemeType = .ibmTerminal
    
    // High-contrast, phosphor green on pure black brutalism
    public let colors = ThemeColors(
        background: Color(red: 0.0, green: 0.0, blue: 0.0),          // #000000
        panelBackground: Color(red: 0.03, green: 0.03, blue: 0.03),  // Pitch grey
        foreground: Color(red: 0.2, green: 1.0, blue: 0.0),          // Phosphor Green #33FF00
        border: Color(red: 0.2, green: 1.0, blue: 0.0).opacity(0.8), // Green outline
        accent: Color(red: 1.0, green: 0.69, blue: 0.0)              // Amber for alerts/warnings
    )
    
    // Assumes IBM Plex Mono is bundled. Fallback is the system monospaced font.
    public let fontName = "IBMPlexMono-Regular"
    
    public func applyPanelStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(12)
                .background(colors.panelBackground)
                .border(colors.border, width: 1) // Strict 1-pixel border, ZERO corner radius
        )
    }
    
    public func applyButtonStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(colors.background)
                .foregroundColor(colors.foreground)
                .border(colors.border, width: 1)
        )
    }
}
