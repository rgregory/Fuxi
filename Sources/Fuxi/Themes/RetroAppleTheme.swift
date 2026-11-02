import SwiftUI

// MARK: - Retro Apple Theme (Classic Mac OS / System 7)

public struct RetroAppleTheme: DashboardTheme {
    public let id: ThemeType = .retroApple
    
    // Classic 1-bit / early Platinum Macintosh aesthetic
    public let colors = ThemeColors(
        background: Color(red: 0.95, green: 0.95, blue: 0.95), // Classic Platinum gray/off-white
        panelBackground: Color.white,
        foreground: Color.black,
        border: Color.black,
        accent: Color.black // Strict monochrome for primary UI elements
    )
    
    // Assumes Chicago, Geneva, or a modern pixel-font equivalent is bundled.
    public let fontName = "Chicago"
    
    public func applyPanelStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(12)
                .background(colors.panelBackground)
                // Thick 2px border mimicking early Mac OS window frames
                .border(colors.border, width: 2) 
                // Hard, 0-radius drop shadow to simulate early 3D window layering
                .shadow(color: colors.border, radius: 0, x: 3, y: 3)
        )
    }
    
    public func applyButtonStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(colors.panelBackground)
                .foregroundColor(colors.foreground)
                .border(colors.border, width: 2)
                // 3D pop effect for buttons
                .shadow(color: colors.border, radius: 0, x: 2, y: 2) 
        )
    }
}
