import AppKit

// Classic layout: standard macOS lists and controls, not themed. View ▸ Theme ▸ Classic.
import Charts
import SwiftUI

private let mono = Font.system(.body, design: .monospaced)

// MARK: Overview

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hostname).font(.title.weight(.semibold))
                    if let t = model.lastRead {
                        Text("Read \(t.formatted(date: .abbreviated, time: .standard))")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    // Left: system facts, severity counts, restart reminder.
                    GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                            GridItem(.flexible(), alignment: .topLeading)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(model.facts) { f in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.label.uppercased()).font(.caption2).foregroundStyle(.secondary)
                                    Text(f.value).font(.system(.callout, design: .monospaced))
                                        .textSelection(.enabled)
                                        .lineLimit(1).minimumScaleFactor(0.85)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            ForEach(Severity.allCases) { s in
                                HStack(spacing: 6) {
                                    SeverityBadge(severity: s)
                                    Text("\(model.count(s))").font(.headline.monospacedDigit())
                                }
                            }
                        }

                        if let days = model.uptimeDays, days >= 14 {
                            Label("Up \(days) days. macOS security updates only take effect after a restart.",
                                  systemImage: "arrow.clockwise.circle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let shutdown = model.abnormalShutdown {
                            Label(shutdown, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } label: {
                        Text("System").font(.headline)
                    }
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    // Right: kernel limits.
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.gauges) { g in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(g.name).font(.callout.weight(.medium))
                                        Spacer()
                                        Text(g.caption).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        Text("\(Int(g.percent.rounded()))%")
                                            .font(.callout.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(g.isWarning ? Color.red : Color.primary)
                                            .frame(minWidth: 40, alignment: .trailing)
                                    }
                                    ProgressView(value: g.percent, total: 100)
                                        .tint(g.isWarning ? .red : g.percent >= 99 ? .orange : .teal)
                                    if let note = g.note {
                                        Text(note).font(.caption2).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } label: {
                        Text("Kernel limits in use").font(.headline)
                    }
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)

                if !model.posture.isEmpty {
                    SecurityPostureBox(items: model.posture)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
    }
}

struct SecurityPostureBox: View {
    let items: [PostureItem]

    private var goodCount: Int { items.filter { $0.status == .good }.count }

    var body: some View {
        GroupBox {
            // One line per item; hover for what it means.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .leading), count: 3),
                      alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: icon(item.status))
                            .foregroundStyle(color(item.status))
                            .frame(width: 16)
                        Text(item.name).font(.callout).lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Text(item.value).font(.caption.monospaced())
                            .foregroundStyle(item.status == .attention ? color(item.status) : .secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .contentShape(Rectangle())
                    .help(item.detail)
                }
            }
            .padding(4)
        } label: {
            HStack {
                Text("Security posture").font(.headline)
                Spacer()
                Text("\(goodCount) of \(items.count) · read-only, hover for details")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func icon(_ s: PostureItem.Status) -> String {
        switch s {
        case .good: return "checkmark.shield.fill"
        case .neutral: return "info.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ s: PostureItem.Status) -> Color {
        switch s {
        case .good: return .green
        case .neutral: return .secondary
        case .attention: return .orange
        }
    }
}

// MARK: Findings

struct FindingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var ui = FindingsUI()

    private var shown: [Finding] {
        model.findings.filter { ui.area == nil || $0.rule.area == ui.area }
    }

    private var selectedWrites: [KernelWrite] {
        model.findings
            .filter { $0.actionable && model.selection.contains($0.id) }
            .compactMap { f in f.target.map { (key: f.rule.key, value: $0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(shown) { FindingRow(finding: $0) }
            }
            Divider()
            HStack {
                Text("\(selectedWrites.count) selected").foregroundStyle(.secondary)
                Spacer()
                if model.isApplying { ProgressView().controlSize(.small) }
                Button("Apply Selected…") {
                    let writes = selectedWrites
                    Task { await model.apply(writes) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedWrites.isEmpty || model.isApplying)
            }
            .padding(12)
        }
        .navigationTitle("Findings")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Area", selection: $ui.area) {
                    Text("All").tag(Area?.none)
                    ForEach(Area.allCases) { Text($0.rawValue).tag(Area?.some($0)) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
        }
    }
}

// MARK: All keys

struct ExplorerView: View {
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

    private var namespaces: [String] {
        Array(Set(model.snapshot.entries.map(\.namespace))).sorted()
    }

    private func entry(_ id: SysctlEntry.ID?) -> SysctlEntry? {
        guard let id else { return nil }
        return model.snapshot.entries.first { $0.key == id }
    }

    var body: some View {
        Table(rows, selection: $ui.selection) {
            TableColumn("Key") { e in
                Text(e.key)
                    .font(mono)
                    .foregroundStyle(Catalog.keys.contains(e.key) ? Color.accentColor : Color.primary)
            }
            .width(min: 220, ideal: 340)
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
        .searchable(text: $ui.query, prompt: "Search keys and values")
        .navigationTitle("All Keys")
        .navigationSubtitle("\(rows.count.formatted()) of \(model.snapshot.entries.count.formatted())")
        .toolbar {
            ToolbarItemGroup {
                Picker("Namespace", selection: $ui.namespace) {
                    Text("All namespaces").tag("")
                    ForEach(namespaces, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 170)
                Toggle(isOn: $ui.flaggedOnly) {
                    Label("Reviewed keys only", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Show only keys Fuxi reviews")
                Button("Set Value…") { ui.editing = entry(ui.selection) }
                    .disabled(ui.selection == nil)
            }
        }
        .sheet(item: $ui.editing) { e in
            SetValueSheet(entry: e).environmentObject(model)
        }
    }
}

// MARK: At boot

struct BootView: View {
    @EnvironmentObject var model: AppModel

    private var keys: [String] { model.managed.keys.sorted() }

    var body: some View {
        VStack(spacing: 0) {
            if keys.isEmpty {
                ContentUnavailableView {
                    Label("No changes to keep", systemImage: "power")
                } description: {
                    Text("Settings you apply from Findings or All Keys show up here. Install them at boot so they survive a restart.")
                }
            } else {
                List {
                    Section("Applied by Fuxi") {
                        ForEach(keys, id: \.self) { key in
                            BootRow(key: key, desired: model.managed[key] ?? "")
                        }
                    }
                    Section(BootConfig.path) {
                        Text(model.bootConfigText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Image(systemName: model.bootConfigInstalled ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.bootConfigInstalled ? (model.bootConfigCurrent ? Color.green : Color.orange) : Color.secondary)
                Text(statusText).foregroundStyle(.secondary)
                Spacer()
                if model.bootConfigInstalled {
                    Button("Remove from Boot…", role: .destructive) { Task { await model.removeBootConfig() } }
                }
                Button(model.bootConfigInstalled ? "Update at Boot…" : "Install at Boot…") {
                    Task { await model.installBootConfig() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keys.isEmpty || (model.bootConfigInstalled && model.bootConfigCurrent))
            }
            .padding(12)
        }
        .navigationTitle("At Boot")
    }

    private var statusText: String {
        if !model.bootConfigInstalled { return "Not installed. Changes reset at restart." }
        if model.bootConfigCurrent { return "Installed. \(BootConfig.path)" }
        return "Installed, but \(BootConfig.path) is out of date."
    }
}

// MARK: History

struct HistoryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView("No changes yet", systemImage: "clock",
                                       description: Text("Every value Fuxi changes is recorded here with its previous value."))
            } else {
                List(model.history) { c in
                    HStack(spacing: 8) {
                        Text(c.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(c.key).font(mono)
                        ValueChip(text: c.oldValue)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        ValueChip(text: c.newValue, accent: true)
                        Spacer()
                        Button("Revert…") { Task { await model.revert(c) } }
                            .disabled(model.isApplying || model.snapshot[c.key] == c.oldValue)
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationSubtitle(model.baselineDate.map { "macOS defaults captured \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
        .toolbar {
            ToolbarItem {
                Button("Clear History") { model.clearHistory() }
                    .disabled(model.history.isEmpty)
            }
        }
    }
}

// MARK: Local view state
// The Command Line Tools toolchain can't load the SwiftUI macro plugin that @State needs
// on the macOS 27 SDK, so local state lives in small ObservableObjects instead.

final class FindingsUI: ObservableObject {
    @Published var area: Area?
}
