import AppKit
import SwiftUI

// The app's layout: sidebar plus card pages, styled by the active theme (Retro or Tron).

private let mono = Font.system(.body, design: .monospaced)
private let pageMaxWidth: CGFloat = 760
private let gutter: CGFloat = 32

extension Pane {
    var tint: Color {
        switch self {
        case .overview: return .blue
        case .findings: return .orange
        case .explorer: return .indigo
        case .boot: return .green
        case .history: return .purple
        }
    }
}

// MARK: Root

struct ThingsRootView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var nav = NavigationUI()

    var body: some View {
        NavigationSplitView {
            ThingsSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            NavigationStack {
                page(nav.pane ?? .overview)
                    .buttonStyle(ThemedButtonStyle())
                    .background(Fx.bg)
            }
            .id(nav.pane ?? .overview)
        }
        .environmentObject(nav)
        .modifier(HideWindowTitle())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay {
            if model.snapshot.entries.isEmpty && model.isLoading {
                ProgressView("Reading kernel settings…")
            }
        }
        .alert(item: $model.alert) { a in
            Alert(title: Text(a.title), message: Text(a.message))
        }
    }

    @ViewBuilder
    private func page(_ pane: Pane) -> some View {
        switch pane {
        case .overview: ThingsOverview()
        case .findings: ThingsFindings()
        case .explorer: ThingsExplorer()
        case .boot: ThingsBoot()
        case .history: ThingsHistory()
        }
    }
}

/// `.toolbar(removing: .title)` needs macOS 15; on 14 an empty title is the closest match.
private struct HideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
        }
    }
}

// MARK: Sidebar

struct ThingsSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: NavigationUI

    var body: some View {
        List(selection: $nav.pane) {
            Section {
                row(.overview)
            }
            Section {
                ForEach([Pane.findings, .explorer, .boot, .history]) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .fxSidebar()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(Fx.font(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isLoading)
                    .help("Read all kernel settings again (⌘R)")
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else if let t = model.lastRead {
                        Text("Read \(t.formatted(date: .omitted, time: .shortened))")
                            .font(Fx.style(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
    }

    private func row(_ p: Pane) -> some View {
        HStack(spacing: 8) {
            Image(systemName: p.icon)
                .font(Fx.font(size: 14, weight: .medium))
                .foregroundStyle(nav.pane == p ? Color.white : p.tint)
                .frame(width: 18)
            Text(p.rawValue).lineLimit(1)
            Spacer(minLength: 4)
            mark(p)
        }
        .help(tooltip(p))
        .tag(p)
    }

    @ViewBuilder
    private func mark(_ p: Pane) -> some View {
        switch p {
        case .overview:
            if model.count(.high) > 0 {
                Circle().fill(Color.red).frame(width: 7, height: 7)
            }
        case .findings:
            quiet(model.findings.filter { $0.actionable }.count)
        case .explorer:
            quiet(model.snapshot.entries.count)
        case .boot:
            if !model.managed.isEmpty && (!model.bootConfigInstalled || !model.bootConfigCurrent) {
                Image(systemName: "exclamationmark.triangle.fill").font(Fx.style(.caption)).foregroundStyle(.orange)
            } else {
                quiet(model.managed.count)
            }
        case .history:
            quiet(model.history.count)
        }
    }

    @ViewBuilder
    private func quiet(_ n: Int) -> some View {
        if n > 0 {
            Text(n.formatted()).font(Fx.style(.callout).monospacedDigit()).foregroundStyle(.tertiary)
        }
    }

    private func tooltip(_ p: Pane) -> String {
        switch p {
        case .overview:
            return model.count(.high) > 0 ? "\(model.count(.high)) high-severity finding(s)" : "System summary"
        case .findings: return "\(model.findings.filter { $0.actionable }.count) recommended changes"
        case .explorer: return "\(model.snapshot.entries.count) kernel settings"
        case .boot:
            if model.managed.isEmpty { return "No changes kept at boot" }
            if !model.bootConfigInstalled { return "Changes reset at restart. Install at boot to keep them." }
            if !model.bootConfigCurrent { return "Startup script is out of date" }
            return "\(model.managed.count) changes kept at boot"
        case .history: return "\(model.history.count) changes recorded"
        }
    }
}

// MARK: Building blocks

struct ThingsScroll<Content: View>: View {
    var maxWidth: CGFloat = pageMaxWidth
    var spacing: CGFloat = 28
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding(.horizontal, gutter)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ThingsHeader: View {
    let pane: Pane
    var title: String? = nil
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(Fx.font(size: 22, weight: .semibold))
                    .foregroundStyle(pane.tint)
                Text(title ?? pane.rawValue).font(Fx.font(size: 26, weight: .bold))
            }
            Text(subtitle)
                .font(Fx.font(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct ThingsSection<Content: View>: View {
    let title: String
    var count: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Fx.theme.applySectionHeader(to: AnyView(
                VStack(spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).font(Fx.font(size: 13, weight: .semibold)).foregroundStyle(Fx.accent)
                        Spacer()
                        if let trailing { trailing }
                        if let count {
                            Text(count).font(Fx.font(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Rectangle().fill(Fx.accent.opacity(0.35)).frame(height: 1)
                }
            ))
            content
        }
    }
}

struct ThingsCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        // The theme's panel adds its own padding.
        Fx.theme.applyPanelStyle(to: AnyView(
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(max(0, padding - 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        ))
    }
}

/// Rows inside a card, separated by inset hairlines.
struct ThingsRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
            if i > 0 { Divider().padding(.leading, 14) }
            row(item).padding(.horizontal, 14)
        }
    }
}

struct PillOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var count: Int? = nil
    var id: String { label }
}

struct ThingsPills<T: Hashable>: View {
    let options: [PillOption<T>]
    @Binding var selection: T

    var body: some View {
        // Scrolls sideways when there are more options than fit (All Keys namespaces).
        ScrollView(.horizontal, showsIndicators: false) {
            FxSegments(selection: $selection, options: options.enumerated().map { (i, o) -> (T, String, KeyboardShortcut?) in
                (o.value, o.count.map { "\(o.label) \($0.formatted())" } ?? o.label,
                 i < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command) : nil)
            })
            .padding(.trailing, 3).padding(.bottom, 3)   // room for the hard shadow
        }
    }
}

// MARK: Overview

struct ThingsOverview: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: NavigationUI

    @ViewBuilder
    private func severityTally(_ levels: [Severity]) -> some View {
        ForEach(levels) { s in
            HStack(spacing: 5) {
                SeverityBadge(severity: s)
                Text("\(model.count(s))").font(Fx.style(.headline).monospacedDigit()).fixedSize()
            }
        }
    }

    private var subtitle: String {
        var parts = [model.hostname]
        if let t = model.lastRead { parts.append("read \(t.formatted(date: .omitted, time: .shortened))") }
        let actionable = model.findings.filter { $0.actionable }.count
        parts.append(actionable == 0 ? "nothing to fix" : "\(actionable) recommended changes")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // Overview is wider than other pages so System and Kernel limits sit side by side.
        ThingsScroll(maxWidth: 1080, spacing: 14) {
            ThingsHeader(pane: .overview, subtitle: subtitle)

            HStack(alignment: .top, spacing: 24) {
                ThingsSection(title: "System") {
                    ThingsCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .topLeading),
                                                GridItem(.flexible(), spacing: 16, alignment: .topLeading)],
                                      alignment: .leading, spacing: 8) {
                                ForEach(model.facts) { f in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(f.label.uppercased()).font(Fx.style(.caption2)).foregroundStyle(.secondary)
                                        Text(f.value)
                                            .font(Fx.style(.callout).monospacedDigit())
                                            .lineLimit(2).minimumScaleFactor(0.8)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            // One row when it fits; wider theme fonts wrap it to two.
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { severityTally(Severity.allCases) }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 10) { severityTally(Array(Severity.allCases.prefix(3))) }
                                    HStack(spacing: 10) { severityTally(Array(Severity.allCases.dropFirst(3))) }
                                }
                            }
                            if let days = model.uptimeDays, days >= 14 {
                                Label("Up \(days) days. macOS security updates only take effect after a restart.",
                                      systemImage: "arrow.clockwise.circle")
                                    .font(Fx.style(.callout))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let shutdown = model.abnormalShutdown {
                                Label(shutdown, systemImage: "exclamationmark.triangle")
                                    .font(Fx.style(.callout))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                ThingsSection(title: "Kernel limits", count: "\(model.gauges.count)") {
                    ThingsCard {
                        ThingsRows(items: model.gauges) { g in ThingsGaugeRow(gauge: g) }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)

            if !model.posture.isEmpty {
                let good = model.posture.filter { $0.status == .good }.count
                let columns = Fx.theme.postureColumns
                let per = (model.posture.count + columns - 1) / columns
                let cols: [[PostureItem]] = stride(from: 0, to: model.posture.count, by: max(per, 1)).map {
                    Array(model.posture[$0..<min($0 + per, model.posture.count)])
                }
                ThingsSection(title: "Security posture", count: "\(good) of \(model.posture.count)") {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(cols.indices, id: \.self) { i in
                            ThingsCard {
                                ThingsRows(items: cols[i]) { item in ThingsPostureRow(item: item) }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ThingsGaugeRow: View {
    let gauge: LimitGauge
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.name).font(Fx.style(.callout))
                Spacer()
                Text(gauge.caption).font(Fx.style(.caption).monospacedDigit()).foregroundStyle(.secondary)
                Text("\(Int(gauge.percent.rounded()))%")
                    .font(Fx.style(.callout).monospacedDigit().weight(.semibold))
                    .foregroundStyle(gauge.isWarning ? Color.red : Fx.fg)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            ProgressView(value: gauge.percent, total: 100)
                .tint(gauge.isWarning ? .red : gauge.percent >= 99 ? .orange : Fx.bar)
            if let note = gauge.note {
                Text(note).font(Fx.style(.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .help(gauge.note ?? gauge.name)
    }
}

/// Single line; the explanation is in the tooltip.
struct ThingsPostureRow: View {
    let item: PostureItem
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            Text(item.name).font(Fx.style(.callout)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(item.value)
                .font(Fx.style(.caption).monospaced())
                .foregroundStyle(item.status == .attention ? Color.orange : Fx.muted)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(item.detail)
    }
    private var icon: String {
        switch item.status {
        case .good: return "checkmark.shield.fill"
        case .neutral: return "info.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        }
    }
    private var color: Color {
        switch item.status {
        case .good: return .green
        case .neutral: return .secondary
        case .attention: return .orange
        }
    }
}

// MARK: Findings

final class ThingsFindingsUI: ObservableObject {
    @Published var area: Area? = nil
}

struct ThingsFindings: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var ui = ThingsFindingsUI()

    private var shown: [Finding] {
        model.findings.filter { ui.area == nil || $0.rule.area == ui.area }
    }

    private var selectedWrites: [KernelWrite] {
        model.findings
            .filter { $0.actionable && model.selection.contains($0.id) }
            .compactMap { f in f.target.map { (key: f.rule.key, value: $0) } }
    }

    private var pills: [PillOption<Area?>] {
        var out: [PillOption<Area?>] = [PillOption<Area?>(value: nil, label: "All", count: model.findings.count)]
        for a in Area.allCases {
            let n = model.findings.filter { $0.rule.area == a }.count
            out.append(PillOption<Area?>(value: a, label: a.rawValue, count: n))
        }
        return out
    }

    var body: some View {
        let actionable = model.findings.filter { $0.actionable }.count
        ThingsScroll {
            VStack(alignment: .leading, spacing: 12) {
                ThingsHeader(pane: .findings,
                             subtitle: actionable == 0 ? "Everything Fuxi reviews is at the recommended value."
                                                       : "\(actionable) recommended changes · \(selectedWrites.count) selected")
                ThingsPills(options: pills, selection: $ui.area)
            }

            ForEach(Severity.allCases) { sev in
                let items = shown.filter { $0.status == sev }
                if !items.isEmpty {
                    ThingsSection(title: sev.label, count: "\(items.count)") {
                        ThingsCard {
                            ThingsRows(items: items) { f in FindingRow(finding: f) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("\(selectedWrites.count) selected").foregroundStyle(.secondary)
                    Spacer()
                    if model.isApplying { ProgressView().controlSize(.small) }
                    Button("Apply Selected…") {
                        let writes = selectedWrites
                        Task { await model.apply(writes) }
                    }
                    .fxProminent()
                    .disabled(selectedWrites.isEmpty || model.isApplying)
                }
                .frame(maxWidth: pageMaxWidth)
                .padding(.horizontal, gutter)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Fx.bg)
        }
    }
}

// MARK: All keys

struct ThingsExplorer: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var ui = ExplorerUI()

    private var rows: [SysctlEntry] {
        let q = ui.query.trimmingCharacters(in: .whitespaces).lowercased()
        let ns = ui.namespace
        let flagged = ui.flaggedOnly
        return model.snapshot.entries.filter { (e: SysctlEntry) -> Bool in
            if !ns.isEmpty && e.namespace != ns { return false }
            if flagged && !Catalog.keys.contains(e.key) { return false }
            if q.isEmpty { return true }
            return e.key.lowercased().contains(q) || e.value.lowercased().contains(q)
        }
    }

    private var pills: [PillOption<String>] {
        var counts: [String: Int] = [:]
        for e in model.snapshot.entries { counts[e.namespace, default: 0] += 1 }
        var out: [PillOption<String>] = [PillOption<String>(value: "", label: "All", count: model.snapshot.entries.count)]
        for ns in counts.keys.sorted() {
            out.append(PillOption<String>(value: ns, label: ns, count: counts[ns]))
        }
        return out
    }

    private func entry(_ id: SysctlEntry.ID?) -> SysctlEntry? {
        guard let id else { return nil }
        return model.snapshot.entries.first { $0.key == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                ThingsHeader(pane: .explorer,
                             subtitle: "\(rows.count.formatted()) of \(model.snapshot.entries.count.formatted()) settings · double-click a row to change it")
                ThingsPills(options: pills, selection: $ui.namespace)
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search keys and values", text: $ui.query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Fx.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Fx.hairline, lineWidth: 0.5))
                Toggle("Reviewed only", isOn: $ui.flaggedOnly)
                    .help("Show only keys Fuxi reviews")
                Button("Set Value…") { ui.editing = entry(ui.selection) }
                    .disabled(ui.selection == nil)
            }
            Table(rows, selection: $ui.selection) {
                TableColumn("Key") { e in
                    Text(e.key)
                        .font(mono)
                        .foregroundStyle(Catalog.keys.contains(e.key) ? Fx.accent : Fx.fg)
                }
                .width(min: 220, ideal: 330)
                TableColumn("Value") { e in
                    Text(e.value).font(mono).lineLimit(2).truncationMode(.tail)
                }
            }
            .contextMenu(forSelectionType: SysctlEntry.ID.self) { ids in
                if let e = entry(ids.first) {
                    Button("Set Value…") { ui.editing = e }
                    Button("Copy “key: value”") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(e.key): \(e.value)", forType: .string)
                    }
                }
            } primaryAction: { ids in
                if let e = entry(ids.first) { ui.editing = e }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Fx.hairline, lineWidth: 0.5))
        }
        .frame(maxWidth: pageMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, gutter)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $ui.editing) { e in
            SetValueSheet(entry: e).environmentObject(model)
        }
    }
}

// MARK: At boot

struct ThingsBoot: View {
    @EnvironmentObject var model: AppModel

    private var keys: [String] { model.managed.keys.sorted() }

    private var status: String {
        if keys.isEmpty { return "Nothing applied yet. Changes you make show up here." }
        if !model.bootConfigInstalled { return "Not installed · changes reset at restart" }
        if model.bootConfigCurrent { return "Installed · \(keys.count) changes kept at every boot" }
        return "Installed, but \(BootConfig.path) is out of date"
    }

    var body: some View {
        ThingsScroll {
            ThingsHeader(pane: .boot, subtitle: status)

            if keys.isEmpty {
                ThingsCard(padding: 20) {
                    Text("Settings you apply from Findings or All Keys appear here. Install them at boot so they survive a restart.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ThingsSection(title: "Status", trailing: nil) {
                    ThingsCard(padding: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: model.bootConfigInstalled ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(model.bootConfigInstalled ? (model.bootConfigCurrent ? Color.green : Color.orange) : Fx.muted)
                            Text(model.bootConfigInstalled ? BootConfig.path : "Not installed")
                                .font(Fx.style(.callout)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if model.bootConfigInstalled {
                                Button("Remove…", role: .destructive) { Task { await model.removeBootConfig() } }
                            }
                            Button(model.bootConfigInstalled ? "Update…" : "Install at Boot…") {
                                Task { await model.installBootConfig() }
                            }
                            .fxProminent()
                            .disabled(model.bootConfigInstalled && model.bootConfigCurrent)
                        }
                    }
                }

                ThingsSection(title: "Kept at boot", count: "\(keys.count)") {
                    ThingsCard {
                        ForEach(Array(keys.enumerated()), id: \.element) { i, key in
                            if i > 0 { Divider().padding(.leading, 14) }
                            BootRow(key: key, desired: model.managed[key] ?? "")
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                }

                ThingsSection(title: BootConfig.path) {
                    ThingsCard(padding: 14) {
                        Text(model.bootConfigText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: History

struct ThingsHistory: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ThingsScroll {
            ThingsHeader(pane: .history,
                         subtitle: model.baselineDate.map { "macOS defaults captured \($0.formatted(date: .abbreviated, time: .shortened))" }
                            ?? "Every value Fuxi changes is recorded with its previous value.")

            if model.history.isEmpty {
                ThingsCard(padding: 20) {
                    Text("No changes yet. Every value Fuxi changes is recorded here with its previous value.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ThingsSection(title: "Changes", count: "\(model.history.count)",
                              trailing: AnyView(
                                Button("Clear") { model.clearHistory() }
                                    .buttonStyle(.link).font(Fx.font(size: 12))
                              )) {
                    ThingsCard {
                        ThingsRows(items: model.history) { c in
                            HStack(spacing: 8) {
                                Text(c.key).font(.system(.callout, design: .monospaced)).lineLimit(1)
                                ValueChip(text: c.oldValue)
                                Image(systemName: "arrow.right").font(Fx.style(.caption)).foregroundStyle(.secondary)
                                ValueChip(text: c.newValue, accent: true)
                                Spacer(minLength: 8)
                                Text(c.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(Fx.style(.caption).monospacedDigit()).foregroundStyle(.secondary)
                                Button("Revert…") { Task { await model.revert(c) } }
                                    .controlSize(.small)
                                    .disabled(model.isApplying || model.snapshot[c.key] == c.oldValue)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }
}
