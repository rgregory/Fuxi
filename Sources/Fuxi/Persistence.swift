import Foundation

struct SettingChange: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let key: String
    let oldValue: String
    let newValue: String
}

struct SavedState: Codable {
    var baseline: [String: String] = [:]
    var baselineDate: Date?
    var history: [SettingChange] = []
    var managed: [String: String] = [:]
}

enum StateStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fuxi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    static func load() -> SavedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(SavedState.self, from: data) else { return SavedState() }
        return state
    }

    static func save(_ state: SavedState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Boot-time persistence through a LaunchDaemon. macOS does not reliably read /etc/sysctl.conf.
enum BootDaemon {
    static let label = "com.fuxi.sysctl"
    static let plistPath = "/Library/LaunchDaemons/com.fuxi.sysctl.plist"
    static let scriptPath = "/usr/local/sbin/fuxi-sysctl.sh"
    static let logPath = "/var/log/fuxi-sysctl.log"

    static func script(for managed: [String: String]) -> String {
        var lines = ["#!/bin/sh", "# Managed by Fuxi. Changes made here are overwritten.", ""]
        for key in managed.keys.sorted() {
            if let value = managed[key], Sysctl.isValidKey(key), Sysctl.isValidValue(value) {
                lines.append("/usr/sbin/sysctl -w \(key)=\(value)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key><string>\(label)</string>
      <key>ProgramArguments</key>
      <array><string>\(scriptPath)</string></array>
      <key>RunAtLoad</key><true/>
      <key>StandardErrorPath</key><string>\(logPath)</string>
    </dict>
    </plist>

    """

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }
    static var installedScript: String? { try? String(contentsOfFile: scriptPath, encoding: .utf8) }

    /// Writes staging files and returns the root command that installs them.
    static func prepareInstall(managed: [String: String]) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fuxi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent("fuxi-sysctl.sh")
        let plistURL = dir.appendingPathComponent("com.fuxi.sysctl.plist")
        try script(for: managed).write(to: scriptURL, atomically: true, encoding: .utf8)
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        return [
            "/bin/mkdir -p /usr/local/sbin",
            "/usr/bin/install -m 755 -o root -g wheel '\(scriptURL.path)' \(scriptPath)",
            "/usr/bin/install -m 644 -o root -g wheel '\(plistURL.path)' \(plistPath)",
            "(/bin/launchctl bootout system/\(label) >/dev/null 2>&1; /bin/sleep 1; /bin/launchctl bootstrap system \(plistPath))",
            "/bin/rm -rf '\(dir.path)'",
        ].joined(separator: " && ")
    }

    static let removeCommand = "/bin/launchctl bootout system/\(label) >/dev/null 2>&1; /bin/rm -f \(plistPath) \(scriptPath)"
}
