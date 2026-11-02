import AppKit
import SwiftUI

// Themes restyle the default layout: page and card backgrounds, text, accent, fonts and the
// prominent buttons. Severity colours stay as they are so High still reads as red.
// The classic layout is not themed.

public enum ThemeType: String, CaseIterable, Identifiable {
    case standard, steampunk, retro, tron

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .steampunk: return "Steampunk"
        case .retro: return "Retro"
        case .tron: return "Tron"
        }
    }

    var theme: any DashboardTheme {
        switch self {
        case .standard: return StandardTheme()
        case .steampunk: return SteampunkTheme()
        case .retro: return RetroTheme()
        case .tron: return TronTheme()
        }
    }

    /// Fonts to try in order when the theme's own font isn't installed.
    var fallbackFonts: [String] {
        switch self {
        case .standard: return []
        case .steampunk: return ["Baskerville", "Georgia"]
        case .retro: return ["CharcoalCY", "Geneva"]
        case .tron: return ["Orbitron", "AvenirNextCondensed-DemiBold", "DINCondensed-Bold"]
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .standard: return nil
        case .retro: return .light
        case .steampunk, .tron: return .dark
        }
    }

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

/// The system look: unchanged from before themes existed.
public struct StandardTheme: DashboardTheme {
    public let id: ThemeType = .standard
    public let colors = ThemeColors(
        background: Color(nsColor: .textBackgroundColor),
        panelBackground: Color(nsColor: .controlBackgroundColor),
        foreground: .primary,
        border: Color.primary.opacity(0.1),
        accent: .accentColor
    )
    public let fontName = ""
    public func applyPanelStyle(to view: AnyView) -> AnyView { view }
    public func applyButtonStyle(to view: AnyView) -> AnyView { view }
}

/// The active theme. Set by the root view before its children are built; the root is keyed
/// on the theme so a switch rebuilds everything.
enum ThemeStore {
    static var current: any DashboardTheme = StandardTheme() {
        didSet { resolvedFont = resolveFont(current) }
    }
    private(set) static var resolvedFont = ""

    private static func resolveFont(_ t: any DashboardTheme) -> String {
        ([t.fontName] + t.id.fallbackFonts).first { !$0.isEmpty && NSFont(name: $0, size: 12) != nil } ?? ""
    }
}

/// Theme lookups for views. Standard returns exactly what the views used before.
enum Fx {
    static var theme: any DashboardTheme { ThemeStore.current }
    static var isStandard: Bool { theme.id == .standard }

    static var bg: Color { theme.colors.background }
    static var panel: Color { theme.colors.panelBackground }
    static var fg: Color { theme.colors.foreground }
    static var accent: Color { theme.colors.accent }
    static var border: Color { theme.colors.border }
    static var muted: Color { isStandard ? .secondary : theme.colors.foreground.opacity(0.6) }
    static var hairline: Color { isStandard ? Color.primary.opacity(0.1) : theme.colors.border.opacity(0.6) }
    /// Gauge fill below the warning level.
    static var bar: Color { isStandard ? .teal : theme.barColor }

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
    /// The main action button: system prominent style, or the theme's button.
    @ViewBuilder func fxProminent() -> some View {
        if Fx.isStandard { buttonStyle(.borderedProminent) } else { buttonStyle(ThemedButtonStyle()) }
    }

    /// Sidebar list background: system material, or the theme's panel colour.
    @ViewBuilder func fxSidebar() -> some View {
        if Fx.isStandard { self } else { scrollContentBackground(.hidden).background(Fx.panel) }
    }
}
