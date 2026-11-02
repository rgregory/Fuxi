import SwiftUI

// MARK: - Retro Theme (Mac OS 9 Platinum)

/// Platinum grey, bevelled panels, pinstriped headers, lavender-blue highlights.
public struct RetroTheme: DashboardTheme {
    public let id: ThemeType = .retro

    public let colors = ThemeColors(
        background: Color(white: 0.87),                          // Platinum desktop grey
        panelBackground: Color(white: 0.93),                     // Window body
        foreground: .black,
        border: .black,
        accent: Color(red: 0.20, green: 0.20, blue: 0.60)        // #333399 highlight text
    )

    /// Charcoal was the OS 9 system font; modern macOS doesn't ship it, so Geneva stands in.
    public let fontName = "Charcoal"

    public var barColor: Color { Color(red: 0.40, green: 0.40, blue: 0.80) }  // #6666CC progress fill
    /// Geneva is wide; three columns would truncate.
    public var postureColumns: Int { 2 }

    public func applyPanelStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(12)
                .background(colors.panelBackground)
                .overlay(Bevel(light: .white, dark: Color(white: 0.55), width: 2))
                .overlay(Rectangle().stroke(Color.black.opacity(0.75), lineWidth: 1))
        )
    }

    public func applyButtonStyle(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .foregroundColor(.black)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [.white, Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                )
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black, lineWidth: 1))
        )
    }

    /// Title on a platinum chip over horizontal pinstripes, like an OS 9 window title bar.
    public func applySectionHeader(to view: AnyView) -> AnyView {
        AnyView(
            view
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.87)))
                        var y: CGFloat = 3
                        while y < size.height - 2 {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                         with: .color(Color(white: 0.70)))
                            y += 2
                        }
                    }
                )
                .overlay(Bevel(light: .white, dark: Color(white: 0.55), width: 1))
        )
    }
}

/// Light top and left edges, dark bottom and right: the raised look of OS 9 controls.
struct Bevel: View {
    let light: Color
    let dark: Color
    let width: CGFloat

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: w, height: width))
                p.addRect(CGRect(x: 0, y: 0, width: width, height: h))
            }
            .fill(light)
            Path { p in
                p.addRect(CGRect(x: 0, y: h - width, width: w, height: width))
                p.addRect(CGRect(x: w - width, y: 0, width: width, height: h))
            }
            .fill(dark)
        }
        .allowsHitTesting(false)
    }
}
