import Foundation

/// Launch-at-login via a per-user LaunchAgent (works for a locally built, ad-hoc signed app).
enum LoginItem {
    private static let label = "local.glassdesk"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ enabled: Bool) {
        guard enabled else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try data.write(to: plistURL)
        } catch {
            NSLog("GlassDesk: could not write login item: \(error)")
        }
    }
}
