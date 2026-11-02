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
    @Published private(set) var daemonInstalled = false
    @Published private(set) var pendingBootArgs: String?
    @Published private(set) var xprotect: XProtectStatus?
    @Published private(set) var installedScript: String?

    private var didSeedSelection = false

    init() {
        state = StateStore.load()
        Task { await refresh() }
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

    var bootScript: String { BootDaemon.script(for: state.managed) }
    var bootScriptCurrent: Bool { installedScript == bootScript }

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

    /// Days since boot, for the restart reminder.
    var uptimeDays: Int? {
        guard let boot = snapshot["kern.boottime"], let sec = firstCapture("sec = (\\d+)", in: boot),
              let t = Double(sec) else { return nil }
        return Int((Date().timeIntervalSince1970 - t) / 86_400)
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
                out[i].note = "Full by design: macOS fills this cache and recycles entries. Raise it only for very large source trees or container images (see “Enlarge the vnode cache”)."
            }
        }
        pair("Open files", "kern.num_files", "kern.maxfiles")
        if let level = snapshot.int("kern.memorystatus_level"), (0...100).contains(level) {
            out.append(LimitGauge(name: "Memory in use", used: Double(100 - level), limit: 100,
                                  caption: "\(level)% available", warnAt: 85,
                                  note: nil))
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
            daemonInstalled = BootDaemon.isInstalled
            pendingBootArgs = await Task.detached(priority: .utility) { Sysctl.pendingBootArgs() }.value
            xprotect = await Task.detached(priority: .utility) { XProtectStatus.read() }.value
            installedScript = BootDaemon.installedScript
            if !didSeedSelection {
                didSeedSelection = true
                selection = Set(findings.filter { $0.actionable && $0.rule.defaultSelected }.map(\.id))
            }
        } catch {
            alert = AlertItem(title: "Could not read kernel settings", message: error.localizedDescription)
        }
    }

    // MARK: Writing

    func apply(_ writes: [KernelWrite]) async {
        guard !writes.isEmpty, !isApplying else { return }
        for w in writes where !(Sysctl.isValidKey(w.key) && Sysctl.isValidValue(w.value)) {
            alert = AlertItem(title: "Value not allowed",
                              message: "\(w.key) = \(w.value) contains characters Fuxi won't pass to a root shell. Use letters, digits, '.', '_', '-', ':' and ','.")
            return
        }
        isApplying = true
        defer { isApplying = false }

        let command = writes
            .map { "\(Sysctl.path) -w \($0.key)=\($0.value) >/dev/null 2>&1 || echo \($0.key)" }
            .joined(separator: "; ")
        let before = snapshot.map
        let prompt = writes.count == 1
            ? "Fuxi wants to set \(writes[0].key) to \(writes[0].value)."
            : "Fuxi wants to change \(writes.count) kernel settings."

        let output: String
        do {
            output = try await Privileged.run(command, prompt: prompt)
        } catch FuxiError.cancelled {
            return
        } catch {
            alert = AlertItem(title: "Not applied", message: error.localizedDescription)
            return
        }

        let failed = Set(output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })

        await refresh()

        var changed: [String] = []
        for w in writes where !failed.contains(w.key) {
            let old = before[w.key] ?? ""
            let now = snapshot[w.key] ?? w.value
            guard old != now else { continue }
            state.history.insert(SettingChange(date: Date(), key: w.key, oldValue: old, newValue: now), at: 0)
            if now == state.baseline[w.key] {
                state.managed.removeValue(forKey: w.key)
            } else {
                state.managed[w.key] = w.value
            }
            changed.append(w.key)
        }
        StateStore.save(state)
        let changedSet = Set(changed)
        selection = selection.filter { id in
            guard let rule = Catalog.rules.first(where: { $0.id == id }) else { return false }
            return !changedSet.contains(rule.key)
        }

        let unchanged = writes.filter { !failed.contains($0.key) && !changedSet.contains($0.key) }.map(\.key)
        var lines: [String] = []
        if !changed.isEmpty { lines.append("Changed: \(changed.joined(separator: ", ")).") }
        if !failed.isEmpty { lines.append("Rejected by the kernel: \(failed.sorted().joined(separator: ", ")). The key may be read-only or the value out of range.") }
        if !unchanged.isEmpty { lines.append("No change: \(unchanged.joined(separator: ", ")).") }
        if !changed.isEmpty { lines.append("These reset at restart unless you install them at boot.") }
        alert = AlertItem(title: failed.isEmpty ? "Applied" : "Partly applied", message: lines.joined(separator: "\n\n"))
    }

    func restoreDefault(_ key: String) async {
        guard let value = state.baseline[key] else { return }
        await apply([(key: key, value: value)])
    }

    func revert(_ change: SettingChange) async {
        await apply([(key: change.key, value: change.oldValue)])
    }

    func stopManaging(_ key: String) {
        state.managed.removeValue(forKey: key)
        StateStore.save(state)
    }

    func clearHistory() {
        state.history.removeAll()
        StateStore.save(state)
    }

    // MARK: Boot daemon

    func installDaemon() async {
        do {
            let command = try BootDaemon.prepareInstall(managed: state.managed)
            _ = try await Privileged.run(command, prompt: "Fuxi wants to install a startup item that applies \(state.managed.count) kernel setting(s) at boot.")
            await refresh()
            alert = AlertItem(title: "Installed at boot", message: "\(BootDaemon.plistPath) runs \(BootDaemon.scriptPath) at every startup.")
        } catch FuxiError.cancelled {
            return
        } catch {
            alert = AlertItem(title: "Not installed", message: error.localizedDescription)
        }
    }

    func removeDaemon() async {
        do {
            _ = try await Privileged.run(BootDaemon.removeCommand, prompt: "Fuxi wants to remove its startup item.")
            await refresh()
            alert = AlertItem(title: "Removed", message: "Settings will return to macOS defaults at the next restart.")
        } catch FuxiError.cancelled {
            return
        } catch {
            alert = AlertItem(title: "Not removed", message: error.localizedDescription)
        }
    }
}
