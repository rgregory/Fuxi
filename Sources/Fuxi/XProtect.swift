import Foundation

/// XProtect state read from files any user can read. No admin rights needed.
struct XProtectStatus {
    /// Signature bundle version (e.g. "5317") and when it was last written.
    var version: String?
    var updated: Date?
    /// XProtect Remediator, the periodic scanner app.
    var remediatorVersion: String?
    /// "Install Security Responses and system files" in Software Update. nil means not set (the default is on).
    var configDataInstall: Bool?
    var criticalUpdateInstall: Bool?

    var automaticUpdatesOn: Bool { (configDataInstall ?? true) && (criticalUpdateInstall ?? true) }

    static func read() -> XProtectStatus {
        var s = XProtectStatus()
        // macOS 15+ keeps the live bundle in /private/var/protected/xprotect; the system copy is the fallback.
        let bundles = [
            "/private/var/protected/xprotect/XProtect.bundle",
            "/Library/Apple/System/Library/CoreServices/XProtect.bundle",
        ]
        var best: (version: String, date: Date?)?
        for b in bundles {
            let plist = b + "/Contents/Info.plist"
            guard let v = bundleVersion(plist) else { continue }
            let date = (try? FileManager.default.attributesOfItem(atPath: plist))?[.modificationDate] as? Date
            if best == nil || newer(v, than: best!.version) { best = (v, date) }
        }
        s.version = best?.version
        s.updated = best?.date
        s.remediatorVersion = bundleVersion("/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist")

        if let prefs = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist") {
            s.configDataInstall = prefs["ConfigDataInstall"] as? Bool
            s.criticalUpdateInstall = prefs["CriticalUpdateInstall"] as? Bool
        }
        return s
    }

    private static func bundleVersion(_ plist: String) -> String? {
        guard let d = NSDictionary(contentsOfFile: plist) else { return nil }
        return (d["CFBundleShortVersionString"] as? String) ?? (d["CFBundleVersion"] as? String)
    }

    private static func newer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}
