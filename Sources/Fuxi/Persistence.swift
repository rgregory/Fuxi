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

/// Boot-time persistence through /etc/sysctl.conf, which macOS reads at startup.
/// macOS services reset a few keys after startup, so a restart is the real test.
enum BootConfig {
    static let path = "/etc/sysctl.conf"
    static let backupPath = "/etc/sysctl.conf.fuxi-backup"
    static let header = "# Managed by Fuxi. Changes made here are overwritten."

    static func text(for managed: [String: String]) -> String {
        var lines = [header, ""]
        for key in managed.keys.sorted() {
            if let value = managed[key], Sysctl.isValidKey(key), Sysctl.isValidValue(value) {
                lines.append("\(key)=\(value)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static var installedText: String? { try? String(contentsOfFile: path, encoding: .utf8) }

    /// True only when the file exists and Fuxi wrote it.
    static var isInstalled: Bool { installedText?.hasPrefix(header) ?? false }

    /// Writes a staging file and returns the root command that installs it. A sysctl.conf
    /// that Fuxi didn't write is copied to the backup path first, once.
    static func prepareInstall(managed: [String: String]) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fuxi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("sysctl.conf")
        try text(for: managed).write(to: fileURL, atomically: true, encoding: .utf8)
        return [
            "if [ -f \(path) ] && [ ! -f \(backupPath) ] && ! /usr/bin/head -1 \(path) | /usr/bin/grep -qF 'Managed by Fuxi'; then /bin/cp -p \(path) \(backupPath); fi",
            "/usr/bin/install -m 644 -o root -g wheel '\(fileURL.path)' \(path)",
            "/bin/rm -rf '\(dir.path)'",
        ].joined(separator: " && ")
    }

    /// Puts back the file Fuxi replaced, or deletes Fuxi's file if there was none.
    static let removeCommand = "if [ -f \(backupPath) ]; then /bin/mv \(backupPath) \(path); else /bin/rm -f \(path); fi"
}
