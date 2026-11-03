import AppKit
import SwiftUI

// Themes restyle the default layout: page and card backgrounds, text, accent, fonts and the
// prominent buttons. Severity colours stay as they are so High still reads as red.

public enum ThemeType: String, CaseIterable, Identifiable {
    case retro, tron

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .retro: return "Retro"
        case .tron: return "Tron"
        }
    }

    var theme: any DashboardTheme {
        switch self {
        case .retro: return RetroTheme()
        case .tron: return TronTheme()
        }
    }

    /// Fonts to try in order when the theme's own font isn't installed.
    var fallbackFonts: [String] {
        switch self {
        case .retro: return []
        case .tron: return ["Orbitron", "AvenirNextCondensed-DemiBold", "DINCondensed-Bold"]
        }
    }

    var colorScheme: ColorScheme { self == .retro ? .light : .dark }

    /// The theme a build was packaged with (Info.plist key FuxiTheme), else Retro.
    static var bundled: ThemeType {
        (Bundle.main.object(forInfoDictionaryKey: "FuxiTheme") as? String).flatMap(ThemeType.init) ?? .retro
    }
}

public struct ThemeColors {
    public let background: Color
    public let panelBackground: Color
    public let foreground: Color
    public let border: Color
    public let accent: Color
}

public protocol DashboardTheme {
    var id: ThemeType { get }
    var colors: ThemeColors { get }
    var fontName: String { get }
    func applyPanelStyle(to view: AnyView) -> AnyView
    func applyButtonStyle(to view: AnyView) -> AnyView
    /// Gauge fill below the warning level.
    var barColor: Color { get }
    /// Wraps a section's title row and rule.
    func applySectionHeader(to view: AnyView) -> AnyView
    /// Columns for the security posture list on the Overview. Wide fonts need fewer.
    var postureColumns: Int { get }
}

public extension DashboardTheme {
    var barColor: Color { colors.foreground }
    func applySectionHeader(to view: AnyView) -> AnyView { view }
    var postureColumns: Int { 3 }
}

/// The active theme. Set by the root view before its children are built; the root is keyed
/// on the theme so a switch rebuilds everything.
enum ThemeStore {
    static var current: any DashboardTheme = RetroTheme() {
        didSet { resolvedFont = resolveFont(current) }
    }
    private(set) static var resolvedFont = ""

    private static func resolveFont(_ t: any DashboardTheme) -> String {
        ([t.fontName] + t.id.fallbackFonts).first { !$0.isEmpty && NSFont(name: $0, size: 12) != nil } ?? ""
    }
}

/// Theme lookups for views.
enum Fx {
    static var theme: any DashboardTheme { ThemeStore.current }
    static var isTron: Bool { theme.id == .tron }

    static var bg: Color { theme.colors.background }
    static var panel: Color { theme.colors.panelBackground }
    static var fg: Color { theme.colors.foreground }
    static var accent: Color { theme.colors.accent }
    static var border: Color { theme.colors.border }
    static var muted: Color { theme.colors.foreground.opacity(0.6) }
    static var hairline: Color { theme.colors.border.opacity(isTron ? 0.6 : 0.25) }
    /// Gauge fill below the warning level.
    static var bar: Color { theme.barColor }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = ThemeStore.resolvedFont
        return name.isEmpty ? .system(size: size, weight: weight) : .custom(name, size: size).weight(weight)
    }

    static func style(_ style: Font.TextStyle) -> Font {
        let name = ThemeStore.resolvedFont
        return name.isEmpty ? .system(style) : .custom(name, size: size(of: style), relativeTo: style)
    }

    private static func size(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline, .body: return 13
        case .callout: return 12
        case .subheadline: return 11
        default: return 10
        }
    }
}

struct ThemedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Fx.theme.applyButtonStyle(to: AnyView(configuration.label.font(Fx.style(.callout))))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// The main action button in the theme's style.
    func fxProminent() -> some View { buttonStyle(ThemedButtonStyle()) }

    /// Sidebar list on the theme's panel colour.
    func fxSidebar() -> some View { scrollContentBackground(.hidden).background(Fx.panel) }
}

// MARK: Controls

/// Checkbox in the theme's style. Retro: square, 2-px black border, black tick.
/// Tron: square cyan outline with a cyan tick.
struct FxCheckbox: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let ink = Fx.isTron ? Fx.accent : Color.black
        return Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Fx.isTron ? Color.clear : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(ink, lineWidth: Fx.isTron ? 1.5 : 2))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundColor(ink)
                        }
                    }
                    .frame(width: 16, height: 16)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One segment strip for filters. Retro: 2-px black border, hard shadow, chosen segment black.
/// Tron: cyan outline, chosen segment cyan.
struct FxSegments<T: Hashable>: View {
    @Binding var selection: T
    /// (value, label, keyboard shortcut) in order.
    let options: [(T, String, KeyboardShortcut?)]

    var body: some View {
        let ink = Fx.isTron ? Fx.accent : Color.black
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                let on = o.0 == selection
                if i > 0 { Rectangle().fill(ink).frame(width: Fx.isTron ? 1 : 2) }
                Button { selection = o.0 } label: {
                    Text(o.1)
                        .font(Fx.font(size: 12, weight: on ? .semibold : .regular))
                        .textCase(Fx.isTron ? .uppercase : nil)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .foregroundColor(on ? (Fx.isTron ? Fx.bg : .white) : (Fx.isTron ? Fx.accent : .black))
                        .background(on ? ink : (Fx.isTron ? Color.clear : Color.white))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(o.2)
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: Fx.isTron ? 0 : 5))
        .overlay(RoundedRectangle(cornerRadius: Fx.isTron ? 0 : 5).strokeBorder(ink, lineWidth: Fx.isTron ? 1 : 2))
        .compositingGroup()
        .shadow(color: Fx.isTron ? Fx.accent.opacity(0.6) : .black,
                radius: Fx.isTron ? 4 : 0, x: Fx.isTron ? 0 : 2, y: Fx.isTron ? 0 : 2)
    }
}
