import AppKit
import SwiftUI

@main
struct FuxiApp: App {
    @StateObject private var model = AppModel()
    /// View ▸ Theme choice. Empty means the theme this build was packaged with.
    @AppStorage("theme") private var themeChoice = ""

    private var themeType: ThemeType { ThemeType(rawValue: themeChoice) ?? .bundled }

    init() {
        // Lets `swift run` show a normal Dock app; harmless inside the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Fuxi") {
            themedRoot()
                .environmentObject(model)
            .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload Settings") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                Picker("Theme", selection: Binding(get: { themeType.rawValue }, set: { themeChoice = $0 })) {
                    ForEach(ThemeType.allCases) { Text($0.title).tag($0.rawValue) }
                }
                // ⇧⌘T flips between them.
                Button(themeType == .tron ? "Switch to Retro" : "Switch to Tron") {
                    themeChoice = (themeType == .tron ? ThemeType.retro : .tron).rawValue
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }

    private func themedRoot() -> some View {
        let type = themeType
        ThemeStore.current = type.theme
        return ThingsRootView()
            // Every button and checkbox takes the theme's style unless it sets its own.
            .buttonStyle(ThemedButtonStyle())
            .toggleStyle(FxCheckbox())
            .font(Fx.style(.body))
            .foregroundStyle(Fx.fg)
            .tint(Fx.accent)
            .preferredColorScheme(type.colorScheme)
            .id(type)
    }
}

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case overview = "Overview"
    case findings = "Findings"
    case explorer = "All Keys"
    case boot = "At Boot"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .findings: return "checklist"
        case .explorer: return "list.bullet.rectangle"
        case .boot: return "power"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

// MARK: Shared pieces

extension Severity {
    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .info: return .gray
        case .ok: return .green
        }
    }
}

struct SeverityBadge: View {
    let severity: Severity
    var body: some View {
        Text(severity.label)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(severity.color)
            .background(severity.color.opacity(0.15), in: Capsule())
    }
}

struct ValueChip: View {
    let text: String
    var accent = false
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accent ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(accent ? Color.accentColor : Color.primary)
    }
}

final class NavigationUI: ObservableObject {
    @Published var pane: Pane? = .overview
}
