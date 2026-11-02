import Foundation

enum Severity: Int, CaseIterable, Comparable, Identifiable {
    case high = 0, medium, low, info, ok

    var id: Int { rawValue }
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .info: return "Info"
        case .ok: return "Good"
        }
    }
}

enum Area: String, CaseIterable, Identifiable {
    case security = "Security"
    case performance = "Performance"
    var id: String { rawValue }
}

struct Rule: Identifiable {
    let id: String
    let area: Area
    let key: String
    let title: String
    let detail: String
    /// Severity shown when the current value is not compliant.
    let failSeverity: Severity
    /// Value Fuxi would write. nil means advisory only.
    let target: (Snapshot) -> String?
    let isCompliant: (String, Snapshot) -> Bool
    var defaultSelected: Bool = true
    var caution: String? = nil
}

struct Finding: Identifiable {
    let rule: Rule
    let current: String?
    let target: String?
    let status: Severity

    var id: String { rule.id }
    var actionable: Bool { target != nil && current != nil && status != .ok && current != target }
}

enum Catalog {
    static func fix(_ id: String, _ area: Area, _ key: String, to value: String, _ severity: Severity,
                    _ title: String, _ detail: String, selected: Bool = true, caution: String? = nil) -> Rule {
        Rule(id: id, area: area, key: key, title: title, detail: detail, failSeverity: severity,
             target: { _ in value }, isCompliant: { cur, _ in cur == value },
             defaultSelected: selected, caution: caution)
    }

    static func atLeast(_ id: String, _ area: Area, _ key: String, _ minimum: Int, _ severity: Severity,
                        _ title: String, _ detail: String, selected: Bool = true, caution: String? = nil) -> Rule {
        Rule(id: id, area: area, key: key, title: title, detail: detail, failSeverity: severity,
             target: { _ in String(minimum) },
             isCompliant: { cur, _ in (Int(cur) ?? 0) >= minimum },
             defaultSelected: selected, caution: caution)
    }

    static func advisory(_ id: String, _ area: Area, _ key: String, _ title: String, _ detail: String,
                         compliant: @escaping (String, Snapshot) -> Bool) -> Rule {
        Rule(id: id, area: area, key: key, title: title, detail: detail, failSeverity: .info,
             target: { _ in nil }, isCompliant: compliant)
    }

    static let rules: [Rule] = [
        // Security
        fix("v6-rediraccept", .security, "net.inet6.icmp6.rediraccept", to: "0", .high,
            "Stop accepting IPv6 redirects",
            "Any host on the same network can send an ICMPv6 redirect and route this Mac's traffic through itself. IPv4 redirects are already dropped by drop_redirect."),
        fix("v4-drop-redirect", .security, "net.inet.icmp.drop_redirect", to: "1", .high,
            "Drop IPv4 redirects",
            "Ignores ICMP redirect messages so other hosts can't rewrite this Mac's routing table."),
        fix("v4-forwarding", .security, "net.inet.ip.forwarding", to: "0", .medium,
            "Turn off IPv4 forwarding",
            "The Mac routes packets between interfaces while this is on.",
            selected: false,
            caution: "Container and VM networking (vmnet) and Internet Sharing need forwarding. Leave it on if you use them."),
        fix("v6-forwarding", .security, "net.inet6.ip6.forwarding", to: "0", .medium,
            "Turn off IPv6 forwarding",
            "IPv6 counterpart of IPv4 forwarding.",
            selected: false,
            caution: "Container and VM networking may need this. Leave it on if you use them."),
        fix("v4-send-redirect", .security, "net.inet.ip.redirect", to: "0", .medium,
            "Don't send IPv4 redirects",
            "A workstation should never advertise routes to other hosts. Safe to turn off even with containers running."),
        fix("v6-send-redirect", .security, "net.inet6.ip6.redirect", to: "0", .medium,
            "Don't send IPv6 redirects",
            "IPv6 counterpart of the setting above. No effect on container NAT."),
        fix("bcast-echo", .security, "net.inet.icmp.bmcastecho", to: "0", .low,
            "Ignore broadcast and multicast pings",
            "Answering pings sent to the broadcast address reveals the Mac on shared networks."),
        fix("coredump", .security, "kern.coredump", to: "0", .low,
            "Turn off core dumps",
            "Crashing processes can write full memory images to /cores, which may contain tokens and keys.",
            selected: false,
            caution: "Leave on if you debug native crashes."),
        fix("tcp-blackhole", .security, "net.inet.tcp.blackhole", to: "2", .low,
            "Stay silent on closed TCP ports",
            "Sends no RST for probes to closed ports, which slows port scans."),
        fix("udp-blackhole", .security, "net.inet.udp.blackhole", to: "1", .low,
            "Stay silent on closed UDP ports",
            "Sends no ICMP port-unreachable for probes to closed UDP ports."),
        fix("source-route", .security, "net.inet.ip.accept_sourceroute", to: "0", .medium,
            "Refuse source-routed packets",
            "Source routing lets a sender choose the path a packet takes. No legitimate use on a workstation."),
        fix("drop-synfin", .security, "net.inet.tcp.drop_synfin", to: "1", .low,
            "Drop SYN+FIN packets",
            "Packets with both flags set are only used for OS fingerprinting."),
        advisory("dev-mode", .security, "security.mac.amfi.developer_mode_status",
                 "Developer Mode",
                 "When on, locally signed and debug builds can run and be attached to. Expected on a development machine. Change it in System Settings › Privacy & Security.",
                 compliant: { cur, _ in cur == "0" }),
        advisory("hibernate", .security, "kern.hibernatemode",
                 "Hibernation image",
                 "Mode 0 writes no memory image to disk at sleep. Mode 3 or 25 writes /var/vm/sleepimage. Change it with pmset, not sysctl.",
                 compliant: { cur, _ in cur == "0" }),

        // Performance
        atLeast("maxvnodes", .performance, "kern.maxvnodes", 524_288, .medium,
                "Enlarge the vnode cache",
                "macOS fills this cache and then recycles the least-recently-used entries, so sitting at the maximum is normal after long uptime. It only costs speed when your active files do not fit: large repositories, node_modules, container layers, or tools that walk the whole disk. Test with a one-boot raise; if it fills again within a day, keep it. Doubling costs a few hundred MB of kernel memory."),
        atLeast("somaxconn", .performance, "kern.ipc.somaxconn", 1024, .low,
                "Raise the listen backlog",
                "Local servers drop connections when bursts exceed the pending-accept queue. Applications still have to request a larger backlog."),
        atLeast("mssdflt", .performance, "net.inet.tcp.mssdflt", 1440, .low,
                "Raise the default TCP MSS",
                "Only used when a peer advertises no MSS. Small gain with path MTU discovery on.",
                selected: false),
        Rule(id: "gpu-wired", area: .performance, key: "iogpu.wired_limit_mb",
             title: "Let the GPU wire more memory",
             detail: "At 0 the GPU may wire roughly two-thirds to three-quarters of RAM. A higher limit lets larger local models load fully on the GPU.",
             failSeverity: .low,
             target: { s in s.int("hw.memsize").map { String($0 / 1_048_576 * 3 / 4) } },
             isCompliant: { cur, _ in cur != "0" },
             defaultSelected: false,
             caution: "Leave at least 8 GB for macOS. Only useful for models larger than about 20 GB."),
        advisory("reass", .performance, "net.inet.tcp.reass.overflows",
                 "TCP reassembly overflows",
                 "Out-of-order segments dropped from the reassembly queue. A high count points to a lossy link such as Wi-Fi or a VPN tunnel, not a kernel limit. Check netstat -s -p tcp on each network.",
                 compliant: { cur, _ in (Int(cur) ?? 0) < 100_000 }),
        advisory("tcp-buffers", .performance, "net.inet.tcp.recvspace",
                 "TCP receive buffer",
                 "Values of 128 KB and up with autotuning are enough for gigabit links. Raising further wastes memory.",
                 compliant: { cur, _ in (Int(cur) ?? 0) >= 131_072 }),
        advisory("shmmax", .performance, "kern.sysv.shmmax",
                 "System V shared memory",
                 "Only matters for older software that uses SysV shared memory, such as some database builds.",
                 compliant: { _, _ in true }),
    ]

    static let keys: Set<String> = Set(rules.map(\.key))

    static func evaluate(_ rule: Rule, in snapshot: Snapshot) -> Finding {
        guard let current = snapshot[rule.key] else {
            return Finding(rule: rule, current: nil, target: nil, status: .info)
        }
        let target = rule.target(snapshot)
        let status: Severity = rule.isCompliant(current, snapshot) ? .ok : rule.failSeverity
        return Finding(rule: rule, current: current, target: target, status: status)
    }
}
