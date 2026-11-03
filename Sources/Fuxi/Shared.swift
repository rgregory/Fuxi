import AppKit
import SwiftUI

// Rows and sheets used by the main layout (Things.swift).

private let mono = Font.system(.body, design: .monospaced)

struct FindingRow: View {
    @EnvironmentObject var model: AppModel
    let finding: Finding

    private var isSelected: Binding<Bool> {
        Binding(
            get: { model.selection.contains(finding.id) },
            set: { on in
                if on { model.selection.insert(finding.id) } else { model.selection.remove(finding.id) }
            }
        )
    }

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SeverityBadge(severity: finding.status)
                    Text(finding.rule.title).font(.headline)
                    Text(finding.rule.area.rawValue).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if finding.actionable, let target = finding.target {
                        Button {
                            Task { await model.apply([(key: finding.rule.key, value: target)]) }
                        } label: {
                            Label("Apply", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.caption.weight(.medium))
                        .disabled(model.isApplying)
                        .opacity(hovering ? 1 : 0)
                        .help("Apply just this change")

                        Toggle("", isOn: isSelected)
                            .labelsHidden()
                            .help("Include in Apply Selected")
                    }
                }
                HStack(spacing: 6) {
                    Text(finding.rule.key).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    ValueChip(text: finding.current ?? "not present")
                    if finding.actionable, let t = finding.target {
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        ValueChip(text: t, accent: true)
                    }
                }
                Text(finding.rule.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if finding.actionable, let caution = finding.rule.caution {
                    Label(caution, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if finding.actionable, let target = finding.target {
                Button(model.selection.contains(finding.id) ? "Deselect" : "Select") {
                    isSelected.wrappedValue.toggle()
                }
                Button("Apply Now…") {
                    Task { await model.apply([(key: finding.rule.key, value: target)]) }
                }
                .disabled(model.isApplying)
            }
            Button("Copy Key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finding.rule.key, forType: .string)
            }
        }
    }
}

struct SetValueSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: SysctlEntry
    @StateObject private var field = TextFieldUI()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set kernel value").font(.title3.weight(.semibold))
            Text(entry.key).font(mono).textSelection(.enabled)
            LabeledContent("Current") {
                Text(entry.value).font(mono).lineLimit(3)
            }
            if let base = model.baseline(entry.key), base != entry.value {
                LabeledContent("macOS default") { Text(base).font(mono) }
            }
            TextField("New value", text: $field.text)
                .textFieldStyle(.roundedBorder)
                .font(mono)
            Text("Fuxi saves a script for you to run with sudo. Many keys are read-only and the kernel will reject them. Values may use letters, digits, '.', '_', '-', ':' and ','.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply…") {
                    let v = field.text.trimmingCharacters(in: .whitespaces)
                    dismiss()
                    Task { await model.apply([(key: entry.key, value: v)]) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!Sysctl.isValidValue(field.text.trimmingCharacters(in: .whitespaces)) || field.text == entry.value)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { field.text = entry.value }
    }
}

// MARK: At boot

struct BootRow: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let desired: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key).font(mono)
            ValueChip(text: desired, accent: true)
            if let current = model.snapshot[key], current != desired {
                Text("Now \(current)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            if let base = model.baseline(key) {
                Text("default \(base)").font(.caption).foregroundStyle(.secondary)
                Button("Restore Default…") { Task { await model.restoreDefault(key) } }
                    .disabled(model.isApplying)
            }
            Button("Stop Keeping") { model.stopManaging(key) }
                .help("Leave the current value but drop it from \(BootConfig.path)")
        }
    }
}

// MARK: Local view state
// The Command Line Tools toolchain can't load the SwiftUI macro plugin that @State needs
// on the macOS 27 SDK, so local state lives in small ObservableObjects instead.

final class ExplorerUI: ObservableObject {
    @Published var query = ""
    @Published var namespace = ""
    @Published var flaggedOnly = false
    @Published var selection: SysctlEntry.ID?
    @Published var editing: SysctlEntry?
}

final class TextFieldUI: ObservableObject {
    @Published var text = ""
}
