import SwiftUI

// MARK: - Tron Theme (The Grid)

/// Black grid, glowing cyan edges, chamfered corners, orange for warnings.
public struct TronTheme: DashboardTheme {
    public let id: ThemeType = .tron

    private static let cyan = Color(red: 0.00, green: 0.90, blue: 1.00)

    public let colors = ThemeColors(
        background: Color(red: 0.00, green: 0.02, blue: 0.05),   // The Grid at night
        panelBackground: Color(red: 0.00, green: 0.05, blue: 0.09),
        foreground: Color(red: 0.78, green: 0.96, blue: 1.00),   // Pale cyan text
        border: TronTheme.cyan,
        accent: TronTheme.cyan
    )

    /// Orbitron if installed; otherwise a condensed sans.
    public let fontName = "Orbitron-Regular"

    public var barColor: Color { TronTheme.cyan }

    public func applyPanelStyle(to view: AnyView) -> AnyView {
        let shape = Chamfered(cut: 12)
        return AnyView(
            view
                .padding(14)
                .background(
                    ZStack {
                        shape.fill(colors.panelBackground)
                        // Faint grid inside each panel.
                        Canvas { context, size in
                            var grid = Path()
                            stride(from: CGFloat(0), through: size.width, by: 24).forEach { x in
                                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                            }
                            stride(from: CGFloat(0), through: size.height, by: 24).forEach { y in
                                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                            }
                            context.stroke(grid, with: .color(TronTheme.cyan.opacity(0.06)), lineWidth: 1)
                        }
                        .clipShape(shape)
                    }
                )
                // Glow on the edge only, so text stays sharp.
                .overlay(shape.stroke(TronTheme.cyan.opacity(0.55), lineWidth: 3).blur(radius: 4))
                .overlay(shape.stroke(TronTheme.cyan, lineWidth: 1))
        )
    }

    public func applyButtonStyle(to view: AnyView) -> AnyView {
        let shape = Chamfered(cut: 7)
        return AnyView(
            view
                .textCase(.uppercase)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .foregroundColor(TronTheme.cyan)
                .background(shape.fill(TronTheme.cyan.opacity(0.08)))
                .overlay(shape.stroke(TronTheme.cyan.opacity(0.6), lineWidth: 3).blur(radius: 3))
                .overlay(shape.stroke(TronTheme.cyan, lineWidth: 1))
        )
    }

    /// Uppercase headings with a soft glow.
    public func applySectionHeader(to view: AnyView) -> AnyView {
        AnyView(
            view
                .textCase(.uppercase)
                .shadow(color: TronTheme.cyan.opacity(0.7), radius: 4)
        )
    }
}

/// A rectangle with the top-left and bottom-right corners cut off.
struct Chamfered: Shape {
    let cut: CGFloat
    func path(in r: CGRect) -> Path {
        let c = min(cut, r.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}
