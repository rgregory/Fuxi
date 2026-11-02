import AppKit
import Foundation
import SwiftUI

typealias KernelWrite = (key: String, value: String)

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct Fact: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct PostureItem: Identifiable {
    enum Status { case good, neutral, attention }
    let name: String
    let value: String
    let status: Status
    let detail: String
    var id: String { name }
}

struct LimitGauge: Identifiable {
    let name: String
    let used: Double
    let limit: Double
    let caption: String
    /// Percent at which the bar turns red. Above 100 means never.
    var warnAt: Double = 90
    var note: String? = nil
    var id: String { name }
    var isWarning: Bool { percent >= warnAt }
    var percent: Double { limit > 0 ? min(100, used / limit * 100) : 0 }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var lastRead: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published var selection: Set<String> = []
    @Published var alert: AlertItem?
    @Published private(set) var state: SavedState
    @Published private(set) var bootConfigInstalled = false
    @Published private(set) var pendingBootArgs: String?
    @Published private(set) var xprotect: XProtectStatus?
    @Published private(set) var installedConfig: String?
    @Published private(set) var processCount: Int?

    private var didSeedSelection = false
    /// Writes in a script the user has saved but Fuxi hasn't yet seen take effect, by key.
    private var pending: [String: (old: String, value: String)] = [:]
    /// True from saving a script until the next read, so returning to Fuxi reloads.
    private var awaitingScript = false
    private var activeObserver: NSObjectProtocol?

    init() {
        state = StateStore.load()
        Task { await refresh() }
        // The user runs the script in Terminal, then switches back: read again so the result shows.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.awaitingScript else { return }
                await self.refresh()
            }
        }
    }

    // MARK: Derived

    var findings: [Finding] {
        Catalog.rules
            .map { Catalog.evaluate($0, in: snapshot) }
            .sorted { ($0.status, $0.rule.area.rawValue, $0.rule.title) < ($1.status, $1.rule.area.rawValue, $1.rule.title) }
    }

    func count(_ severity: Severity) -> Int { findings.filter { $0.status == severity }.count }

    var managed: [String: String] { state.managed }
    var history: [SettingChange] { state.history }
    func baseline(_ key: String) -> String? { state.baseline[key] }
    var baselineDate: Date? { state.baselineDate }

    var bootConfigText: String { BootConfig.text(for: state.managed) }
    var bootConfigCurrent: Bool { installedConfig == bootConfigText }

    /// Read-only security state reported by the kernel. Nothing here can be changed with sysctl.
    var posture: [PostureItem] {
        var out: [PostureItem] = []
        func flag(_ name: String, _ key: String, on: String = "On", off: String = "Off",
                  goodWhen expected: Int, badStatus: PostureItem.Status = .attention, _ detail: String) {
            guard let v = snapshot.int(key) else { return }
            let isOn = v != 0
            let good = (v != 0 ? 1 : 0) == expected
            out.append(PostureItem(name: name, value: isOn ? on : off,
                                   status: good ? .good : badStatus, detail: detail))
        }
        flag("Gatekeeper", "security.mac.asp.policy.gatekeeper_enabled", goodWhen: 1,
             "Checks downloaded apps for a valid signature and notarization before they first open.")
        flag("Quarantine", "security.mac.qtn.sandbox_enforce", goodWhen: 1,
             "Downloaded files carry the quarantine flag until you approve them.")
        if let xp = xprotect {
            if let v = xp.version {
                var value = "v\(v)"
                var status = PostureItem.Status.good
                var detail = "Malware signatures Gatekeeper checks apps against. Apple updates them in the background."
                if let d = xp.updated {
                    let days = Int(Date().timeIntervalSince(d) / 86_400)
                    value += days == 0 ? " · today" : " · \(days) d ago"
                    if days > 30 {
                        status = .attention
                        detail = "Signatures have not changed in \(days) days. Apple usually ships updates every few weeks; check Software Update."
                    }
                }
                out.append(PostureItem(name: "XProtect", value: value, status: status, detail: detail))
            } else {
                out.append(PostureItem(name: "XProtect", value: "Not found", status: .attention,
                                       detail: "The XProtect signature bundle could not be read."))
            }
            if let r = xp.remediatorVersion {
                out.append(PostureItem(name: "XProtect Remediator", value: "v\(r)", status: .good,
                                       detail: "Scans the Mac periodically and removes known malware it finds."))
            }
            out.append(PostureItem(name: "Security data updates", value: xp.automaticUpdatesOn ? "Automatic" : "Off",
                                   status: xp.automaticUpdatesOn ? .good : .attention,
                                   detail: xp.automaticUpdatesOn
                                       ? "XProtect signatures and Rapid Security Responses install on their own."
                                       : "“Install Security Responses and system files” is off in Software Update, so XProtect falls behind."))
        }
        flag("Launch constraints", "security.mac.amfi.launch_constraints_enforced", goodWhen: 1,
             "Limits which processes may launch Apple's system binaries.")
        flag("Kill on bad signature", "security.mac.amfi.forced_cs_kill", goodWhen: 1,
             "A process whose code signature becomes invalid while running is stopped.")
        flag("App Management", "security.mac.sandbox.appprotection.enabled", goodWhen: 1,
             "Stops one app from modifying another without your permission.")

        let enforceKeys = snapshot.entries.map(\.key)
            .filter { $0.hasPrefix("security.mac.") && $0.hasSuffix("_enforce") && $0.split(separator: ".").count == 3 }
        if !enforceKeys.isEmpty {
            let off = enforceKeys.filter { snapshot.int($0) == 0 }
                .map { $0.replacingOccurrences(of: "security.mac.", with: "").replacingOccurrences(of: "_enforce", with: "") }
            out.append(PostureItem(name: "Kernel access checks",
                                   value: off.isEmpty ? "All \(enforceKeys.count) on" : "\(off.count) off",
                                   status: off.isEmpty ? .good : .attention,
                                   detail: off.isEmpty ? "Mandatory access control is enforced on every kernel object type."
                                                       : "Not enforced for: \(off.joined(separator: ", "))."))
        }
        if let m = snapshot.int("security.codesigning.monitor") {
            out.append(PostureItem(name: "Code-signing monitor", value: m > 0 ? "Active" : "Off",
                                   status: m > 0 ? .good : .attention,
                                   detail: "Hardware-protected layer that guards executable memory on Apple silicon."))
        }
        if let n = snapshot.int("security.codesigning.trustcaches.num_engineering") {
            out.append(PostureItem(name: "Engineering trust caches", value: n == 0 ? "None" : "\(n) loaded",
                                   status: n == 0 ? .good : .attention,
                                   detail: "Apple-internal binary allow-lists. A retail Mac should have none."))
        }
        flag("Apple QA certificates", "security.mac.amfi.qa_root_certs_allowed",
             on: "Trusted", off: "Not trusted", goodWhen: 0,
             "Apple's internal test signing certificates. Should not be trusted on a retail Mac.")
        flag("Security research device", "hw.features.allows_security_research",
             on: "Yes", off: "No", goodWhen: 0,
             "Apple's research hardware with protections relaxed for testing.")
        if let args = snapshot["kern.bootargs"] {
            let a = args.trimmingCharacters(in: .whitespaces)
            out.append(PostureItem(name: "Boot arguments", value: a.isEmpty ? "None" : a,
                                   status: a.isEmpty ? .good : .attention,
                                   detail: "Arguments the running kernel booted with. Custom ones need Reduced Security on Apple silicon."))
        }
        if let pending = pendingBootArgs {
            let current = snapshot["kern.bootargs"]?.trimmingCharacters(in: .whitespaces) ?? ""
            let detail: String
            if pending.isEmpty {
                detail = "Nothing is queued in NVRAM for the next restart."
            } else if pending == current {
                detail = "Stored in NVRAM and already in use."
            } else {
                detail = "Stored in NVRAM and not yet in use. Takes effect at the next restart if Startup Security allows it."
            }
            out.append(PostureItem(name: "Next-boot arguments", value: pending.isEmpty ? "None" : pending,
                                   status: pending.isEmpty ? .good : .attention, detail: detail))
        }
        flag("Developer Mode", "security.mac.amfi.developer_mode_status", goodWhen: 0, badStatus: .neutral,
             "Lets debuggers attach to processes and locally signed builds run. Expected on a development Mac.")
        flag("Lockdown Mode", "security.mac.lockdown_mode_state", goodWhen: 1, badStatus: .neutral,
             "Extreme protection for targeted users. Disables many features; off is normal.")
        return out
    }

    private var uptimeSeconds: Double? {
        guard let boot = snapshot["kern.boottime"], let sec = firstCapture("sec = (\\d+)", in: boot),
              let t = Double(sec) else { return nil }
        return Date().timeIntervalSince1970 - t
    }

    /// Days since boot, for the restart reminder.
    var uptimeDays: Int? { uptimeSeconds.map { Int($0 / 86_400) } }

    /// Why the previous boot ended, when it wasn't clean. nil for a normal or unrecognised reason.
    var abnormalShutdown: String? {
        guard let r = snapshot["kern.shutdownreason"]?.lowercased() else { return nil }
        if r.contains("panic") { return "Last restart followed a kernel panic." }
        if r.contains("wdog") { return "Last restart followed a watchdog reset: the Mac stopped responding." }
        return nil
    }

    /// Vnodes recycled per hour since boot, rounded to hundreds.
    private var vnodeRecyclesPerHour: Int? {
        guard let n = snapshot.int("kern.num_recycledvnodes"), let up = uptimeSeconds, up > 3600 else { return nil }
        return Int((Double(n) / (up / 3600) / 100).rounded()) * 100
    }

    /// "Compressor holds 18.9 GiB in 8.6 GiB (2.2 : 1)."
    private var compressorNote: String? {
        guard let pages = snapshot.int("vm.compressor.pages_compressed"), pages > 0,
              let used = snapshot.int("vm.compressor_bytes_used"), used > 0 else { return nil }
        let page = snapshot.int("hw.pagesize") ?? 16_384
        let held = Double(pages * page) / 1_073_741_824
        let stored = Double(used) / 1_073_741_824
        return String(format: "Compressor holds %.1f GiB in %.1f GiB (%.1f : 1).", held, stored, held / stored)
    }

    var hostname: String { snapshot["kern.hostname"] ?? "This Mac" }

    var facts: [Fact] {
        var out: [Fact] = []
        func add(_ label: String, _ value: String?) { if let value, !value.isEmpty { out.append(Fact(label: label, value: value)) } }
        add("Model", snapshot["hw.model"])
        add("Chip", snapshot["machdep.cpu.brand_string"])
        if let p0 = snapshot.int("hw.perflevel0.physicalcpu"), let p1 = snapshot.int("hw.perflevel1.physicalcpu") {
            let n0 = snapshot["hw.perflevel0.name"] ?? "Performance"
            let n1 = snapshot["hw.perflevel1.name"] ?? "Efficiency"
            add("Cores", "\(p0) \(n0) + \(p1) \(n1)")
        } else {
            add("Cores", snapshot["hw.physicalcpu"])
        }
        if let mem = snapshot.int("hw.memsize") {
            let page = (snapshot.int("hw.pagesize") ?? 16384) / 1024
            add("Memory", "\(mem / 1_073_741_824) GiB · \(page) KiB pages")
        }
        if let v = snapshot["kern.osproductversion"] {
            add("macOS", "\(v) (\(snapshot["kern.osversion"] ?? "?"))")
        }
        add("Darwin", snapshot["kern.osrelease"])
        if let boot = snapshot["kern.boottime"], let sec = firstCapture("sec = (\\d+)", in: boot), let t = Double(sec) {
            let up = Date().timeIntervalSince1970 - t
            let days = Int(up / 86_400), hours = Int(up.truncatingRemainder(dividingBy: 86_400) / 3600)
            add("Uptime", "\(days) d \(hours) h")
        }
        if let load = snapshot["vm.loadavg"] {
            let text = load.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
            let first = text.split(separator: " ").first.flatMap { Double($0) }
            if let first, let cpus = snapshot.int("hw.logicalcpu") ?? snapshot.int("hw.ncpu"), cpus > 0 {
                add("Load average", "\(text) · \(String(format: "%.2f", first / Double(cpus)))/core")
            } else {
                add("Load average", text)
            }
        }
        if let p = snapshot.int("kern.memorystatus_vm_pressure_level") {
            add("Memory pressure", p >= 4 ? "Critical" : p >= 2 ? "Warning" : "Normal")
        }

        add("Keys read", snapshot.entries.isEmpty ? nil : snapshot.entries.count.formatted())
        return out
    }

    var gauges: [LimitGauge] {
        var out: [LimitGauge] = []
        func pair(_ name: String, _ used: String, _ limit: String) {
            if let u = snapshot.int(used), let l = snapshot.int(limit), l > 0 {
                out.append(LimitGauge(name: name, used: Double(u), limit: Double(l), caption: "\(u.formatted()) / \(l.formatted())"))
            }
        }
        pair("Vnode cache", "kern.num_vnodes", "kern.maxvnodes")
        if let i = out.firstIndex(where: { $0.name == "Vnode cache" }) {
            out[i].warnAt = 101
            if out[i].percent >= 99 {
                if let rate = vnodeRecyclesPerHour {
                    out[i].note = "Full by design. Recycling about \(rate.formatted()) an hour since boot; raise it only if that climbs (see “Enlarge the vnode cache”)."
                } else {
                    out[i].note = "Full by design: macOS fills this cache and recycles entries. Raise it only for very large source trees or container images (see “Enlarge the vnode cache”)."
                }
            }
        }
        pair("Open files", "kern.num_files", "kern.maxfiles")
        if let n = processCount, let limit = snapshot.int("kern.maxproc"), limit > 0 {
            out.append(LimitGauge(name: "Processes", used: Double(n), limit: Double(limit),
                                  caption: "\(n.formatted()) / \(limit.formatted())"))
        }
        if let level = snapshot.int("kern.memorystatus_level"), (0...100).contains(level) {
            out.append(LimitGauge(name: "Memory in use", used: Double(100 - level), limit: 100,
                                  caption: "\(level)% available", warnAt: 85,
                                  note: compressorNote))
        }
        if let swap = snapshot["vm.swapusage"],
           let total = firstCapture("total = ([0-9.]+)M", in: swap).flatMap(Double.init),
           let used = firstCapture("used = ([0-9.]+)M", in: swap).flatMap(Double.init), total > 0 {
            out.append(LimitGauge(name: "Swap", used: used, limit: total,
                             caption: "\(Int(used)) MB / \(Int(total)) MB"))
        }
        return out
    }

    // MARK: Reading

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await Task.detached(priority: .userInitiated) { try Sysctl.readAll() }.value
            snapshot = Snapshot(entries: entries)
            lastRead = Date()
            if state.baseline.isEmpty {
                state.baseline = snapshot.map
                state.baselineDate = Date()
                StateStore.save(state)
            }
            bootConfigInstalled = BootConfig.isInstalled
            pendingBootArgs = await Task.detached(priority: .utility) { Sysctl.pendingBootArgs() }.value
            xprotect = await Task.detached(priority: .utility) { XProtectStatus.read() }.value
            installedConfig = BootConfig.installedText
            processCount = await Task.detached(priority: .utility) { Sysctl.processCount() }.value
            awaitingScript = false
            reconcilePending()
            if !didSeedSelection {
                didSeedSelection = true
                selection = Set(findings.filter { $0.actionable && $0.rule.defaultSelected }.map(\.id))
            }
        } catch {
            alert = AlertItem(title: "Could not read kernel settings", message: error.localizedDescription)
        }
    }

    // MARK: Writing
    //
    // Fuxi never runs anything as root. Every change is exported as a shell script that
    // the user reads and runs with sudo; the next read records what actually changed.

    func apply(_ writes: [KernelWrite]) async {
        guard !writes.isEmpty else { return }
        for w in writes where !(Sysctl.isValidKey(w.key) && Sysctl.isValidValue(w.value)) {
            alert = AlertItem(title: "Value not allowed",
                              message: "\(w.key) = \(w.value) contains characters Fuxi won't write into a script run as root. Use letters, digits, '.', '_', '-', ':' and ','.")
            return
        }
        let script = ScriptExport.applyScript(writes, current: snapshot.map, host: hostname)
        guard let url = ScriptExport.save(script, suggestedName: "fuxi-apply.sh",
                                          message: "Save a script that changes \(writes.count) kernel setting(s). Run it with sudo.")
        else { return }
        for w in writes {
            pending[w.key] = (old: snapshot[w.key] ?? "", value: w.value)
        }
        awaitingScript = true
        alert = AlertItem(title: "Script saved",
                          message: ScriptExport.instructions(for: url) + "\n\nChanges made this way reset at restart unless you install them at boot.")
    }

    func restoreDefault(_ key: String) async {
        guard let value = state.baseline[key] else { return }
        await apply([(key: key, value: value)])
    }

    func revert(_ change: SettingChange) async {
        await apply([(key: change.key, value: change.oldValue)])
    }

    /// Records writes from a saved script once the kernel shows them.
    private func reconcilePending() {
        guard !pending.isEmpty else { return }
        var changed: [String] = []
        for (key, p) in pending {
            guard let now = snapshot[key], now != p.old else { continue }
            state.history.insert(SettingChange(date: Date(), key: key, oldValue: p.old, newValue: now), at: 0)
            if now == state.baseline[key] {
                state.managed.removeValue(forKey: key)
            } else {
                state.managed[key] = p.value
            }
            pending.removeValue(forKey: key)
            changed.append(key)
        }
        guard !changed.isEmpty else { return }
        StateStore.save(state)
        let changedSet = Set(changed)
        selection = selection.filter { id in
            guard let rule = Catalog.rules.first(where: { $0.id == id }) else { return false }
            return !changedSet.contains(rule.key)
        }
        var lines = ["Changed: \(changed.sorted().joined(separator: ", "))."]
        if !pending.isEmpty {
            lines.append("Not changed yet: \(pending.keys.sorted().joined(separator: ", ")). If the script reported them as rejected, the key is read-only or the value is out of range.")
        }
        alert = AlertItem(title: "Applied", message: lines.joined(separator: "\n\n"))
    }

    func stopManaging(_ key: String) {
        state.managed.removeValue(forKey: key)
        StateStore.save(state)
    }

    func clearHistory() {
        state.history.removeAll()
        StateStore.save(state)
    }

    // MARK: At boot

    func installBootConfig() async {
        let script = ScriptExport.installBootScript(BootConfig.text(for: state.managed), host: hostname)
        guard let url = ScriptExport.save(script, suggestedName: "fuxi-boot-install.sh",
                                          message: "Save a script that writes \(state.managed.count) setting(s) to \(BootConfig.path). Run it with sudo.")
        else { return }
        awaitingScript = true
        alert = AlertItem(title: "Script saved",
                          message: ScriptExport.instructions(for: url) + "\n\nmacOS reads \(BootConfig.path) at startup. After a restart, check this list: macOS resets a few keys after startup, and those need setting again.")
    }

    func removeBootConfig() async {
        let script = ScriptExport.removeBootScript(host: hostname)
        guard let url = ScriptExport.save(script, suggestedName: "fuxi-boot-remove.sh",
                                          message: "Save a script that removes Fuxi's \(BootConfig.path). Run it with sudo.")
        else { return }
        awaitingScript = true
        alert = AlertItem(title: "Script saved",
                          message: ScriptExport.instructions(for: url) + "\n\nSettings return to macOS defaults at the next restart. Any sysctl.conf you had before Fuxi is put back.")
    }
}
