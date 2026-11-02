import Foundation

struct SysctlEntry: Identifiable, Hashable {
    let key: String
    let value: String
    var id: String { key }
    var namespace: String { String(key.split(separator: ".").first ?? "") }
}

struct Snapshot {
    var entries: [SysctlEntry] = []
    var map: [String: String] = [:]

    init() {}

    init(entries: [SysctlEntry]) {
        self.entries = entries
        self.map = Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    subscript(_ key: String) -> String? { map[key] }

    func int(_ key: String) -> Int? {
        map[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

enum FuxiError: LocalizedError {
    case launchFailed(String)
    case notAllowed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let m): return "Could not run sysctl: \(m)"
        case .notAllowed(let m): return m
        }
    }
}

enum Sysctl {
    static let path = "/usr/sbin/sysctl"

    private static let keyChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    private static let valueChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:,")

    /// Keys and values are passed to a root shell, so only a narrow character set is accepted.
    static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 128 && key.contains(".") && !key.hasPrefix("-")
            && key.unicodeScalars.allSatisfy { keyChars.contains($0) }
    }

    static func isValidValue(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && !value.hasPrefix("-")
            && value.unicodeScalars.allSatisfy { valueChars.contains($0) }
    }

    /// Running processes, from the kernel's process table. No root needed.
    static func processCount() -> Int? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        let stride = MemoryLayout<kinfo_proc>.stride
        // Leave room for processes started between the two calls.
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = procs.count * stride
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else { return nil }
        return size / stride
    }

    static func readAll() throws -> [SysctlEntry] {
        parse(try run(path, ["-a"]))
    }

    static func parse(_ text: String) -> [SysctlEntry] {
        var result: [SysctlEntry] = []
        var seen = Set<String>()
        var currentKey: String?
        var currentValue = ""

        func flush() {
            guard let k = currentKey, !seen.contains(k) else { return }
            seen.insert(k)
            result.append(SysctlEntry(key: k, value: currentValue.trimmingCharacters(in: .whitespaces)))
        }

        for sub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(sub)
            var split: Range<String.Index>?
            if let r = line.range(of: ": ") {
                split = r
            } else if line.hasSuffix(":") {
                split = line.range(of: ":", options: .backwards)
            }
            if let r = split {
                let k = String(line[..<r.lowerBound])
                if isValidKey(k) {
                    flush()
                    currentKey = k
                    currentValue = String(line[r.upperBound...])
                    continue
                }
            }
            if currentKey != nil, !line.isEmpty {
                currentValue += "\n" + line
            }
        }
        flush()
        return result
    }

    /// Boot arguments stored in NVRAM for the next boot. "" when none are set, nil if nvram could not run.
    /// `nvram boot-args` prints "boot-args<TAB>value", or only an error on stderr when the variable is absent.
    static func pendingBootArgs() -> String? {
        guard let out = try? run("/usr/sbin/nvram", ["boot-args"]) else { return nil }
        let line = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("boot-args") else { return "" }
        return String(line.dropFirst("boot-args".count)).trimmingCharacters(in: .whitespaces)
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw FuxiError.launchFailed(error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

func firstCapture(_ pattern: String, in s: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}
