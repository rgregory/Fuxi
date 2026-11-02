import SwiftUI

// MARK: - Steampunk Theme (Brass, Glass, & Clockwork)

public struct SteampunkTheme: DashboardTheme {
    public let id: ThemeType = .steampunk
    
    // Rich mahogany, tarnished brass, and amber glass aesthetics
    public let colors = ThemeColors(
        background: Color(red: 0.12, green: 0.08, blue: 0.05), // Dark Mahogany / Leather
        panelBackground: Color(red: 0.15, green: 0.10, blue: 0.06), // Recessed wood
        foreground: Color(red: 0.90, green: 0.75, blue: 0.45), // Tarnished Gold / Brass text
        border: Color(red: 0.70, green: 0.45, blue: 0.20), // Copper/Brass mechanics
        accent: Color(red: 0.30, green: 0.85, blue: 0.95) // Aether / Steam blue glow for warnings
    )
    
    public let fontName = "HoeflerText-Regular" 
    
    public func applyPanelStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(20)
                .background(
                    ZStack {
                        Color.black.opacity(0.6)
                        
                        Canvas { context, size in
                            let w = size.width
                            let h = size.height
                            
                            var bracketPath = Path()
                            let cornerSize: CGFloat = 24
                            
                            bracketPath.move(to: CGPoint(x: 0, y: cornerSize))
                            bracketPath.addLine(to: CGPoint(x: 0, y: 0))
                            bracketPath.addLine(to: CGPoint(x: cornerSize, y: 0))
                            
                            bracketPath.move(to: CGPoint(x: w, y: h - cornerSize))
                            bracketPath.addLine(to: CGPoint(x: w, y: h))
                            bracketPath.addLine(to: CGPoint(x: w - cornerSize, y: h))
                            
                            context.stroke(
                                bracketPath,
                                with: .color(colors.border),
                                lineWidth: 4
                            )
                            
                            let center = CGPoint(x: w/2, y: h/2)
                            let radius = min(w, h) * 0.35
                            var etchedCircle = Path()
                            etchedCircle.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                            
                            context.stroke(
                                etchedCircle,
                                with: .color(colors.foreground.opacity(0.1)),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 6])
                            )
                        }
                    }
                )
                .overlay(
                    Rectangle()
                        .stroke(
                            LinearGradient(
                                colors: [colors.foreground, colors.border, colors.foreground.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .compositingGroup()
                .shadow(color: .black.opacity(0.9), radius: 8, x: 0, y: 6)
        )
    }
    
    public func applyButtonStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.4, green: 0.25, blue: 0.1), Color(red: 0.2, green: 0.1, blue: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundColor(colors.foreground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [colors.foreground, colors.border],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
                .cornerRadius(20)
                .compositingGroup()
                .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 3)
        )
    }
}
