import Foundation

/// Installs and removes the one configuration change AI Limits makes to
/// anything outside its own directories: Claude Code's `statusLine` setting.
///
/// This is the only writer to `~/.claude` in the entire codebase, and
/// `scripts/check-safety.sh` fails the build if another one appears.
///
/// Safety properties, each covered by a test:
///  - The original `settings.json` is copied to `settings.json.ailimits-backup`
///    before the first edit, and never overwritten by a second install.
///  - The previous `statusLine` value is recorded verbatim and restored on
///    uninstall. Uninstall touches *only* that key, so settings changed after
///    installing survive.
///  - Every other key in the file is preserved. The file is re-serialised, so
///    key order and whitespace may change; the backup holds the original bytes.
public struct ClaudeHookInstaller {
    public enum InstallError: Error, LocalizedError {
        case settingsNotValidJSON(path: String)

        public var errorDescription: String? {
            switch self {
            case .settingsNotValidJSON(let path):
                return "\(path) is not valid JSON. AI Limits left it untouched."
            }
        }
    }

    /// How often Claude Code re-runs the status line while a session sits
    /// idle. Ten seconds keeps the widget current during a session at
    /// negligible cost — the shim is a compiled binary that does a single
    /// small write.
    public static let refreshIntervalSeconds = 10

    private let paths: Paths

    public init(paths: Paths = Paths()) {
        self.paths = paths
    }

    // MARK: - State

    private struct HookState: Codable {
        let installedAt: Date
        let shimPath: String
        /// The user's previous `statusLine` value, as raw JSON. Absent when
        /// they had no status line configured at all.
        let previousStatusLineJSON: String?
    }

    public func isInstalled() -> Bool {
        guard let settings = readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String
        else { return false }
        return command.contains(Self.shimExecutableName)
    }

    public static let shimExecutableName = "ai-limits-statusline"

    // MARK: - Install

    public func install(shimPath: URL) throws {
        var settings = try requireSettings()

        // Installing twice must not record our own hook as the "previous"
        // value, which would make uninstall a no-op that leaves it in place.
        if !isInstalled() {
            try backUpSettingsIfNeeded()
            try writeHookState(
                HookState(
                    installedAt: Date(),
                    shimPath: shimPath.path,
                    previousStatusLineJSON: currentStatusLineJSON(in: settings)
                )
            )
        }

        settings["statusLine"] = [
            "type": "command",
            "command": shimPath.path,
            "refreshInterval": Self.refreshIntervalSeconds,
        ]
        try writeSettings(settings)
    }

    // MARK: - Uninstall

    /// Puts `statusLine` back exactly as it was and leaves every other setting
    /// alone, so anything changed since installing is preserved.
    public func uninstall() throws {
        guard var settings = readSettings() else { return }

        let state = readHookState()
        if let json = state?.previousStatusLineJSON,
           let data = json.data(using: .utf8),
           let previous = try? JSONSerialization.jsonObject(with: data) {
            settings["statusLine"] = previous
        } else {
            settings.removeValue(forKey: "statusLine")
        }

        try writeSettings(settings)
        try? FileManager.default.removeItem(at: paths.hookState)
    }

    // MARK: - settings.json

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: paths.claudeSettings) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// A missing settings file is fine — Claude Code creates one on demand and
    /// so do we. A *corrupt* one is not: rewriting it would destroy settings
    /// we cannot read, so we refuse and say so.
    private func requireSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: paths.claudeSettings.path) else { return [:] }
        guard let settings = readSettings() else {
            throw InstallError.settingsNotValidJSON(path: paths.claudeSettings.path)
        }
        return settings
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try SnapshotStore.writeAtomically(data: data, to: paths.claudeSettings)
        // settings.json is the user's file, not ours; 0600 would be a change
        // in its own right, so it keeps the permissions Claude Code gave it.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: paths.claudeSettings.path
        )
    }

    private func currentStatusLineJSON(in settings: [String: Any]) -> String? {
        guard let statusLine = settings["statusLine"],
              let data = try? JSONSerialization.data(withJSONObject: statusLine)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func backUpSettingsIfNeeded() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: paths.claudeSettings.path),
              !manager.fileExists(atPath: paths.claudeSettingsBackup.path)
        else { return }
        try manager.copyItem(at: paths.claudeSettings, to: paths.claudeSettingsBackup)
    }

    // MARK: - Hook state

    private func writeHookState(_ state: HookState) throws {
        try SnapshotStore.writeAtomically(
            data: SnapshotStore.encoder.encode(state),
            to: paths.hookState
        )
    }

    private func readHookState() -> HookState? {
        guard let data = try? Data(contentsOf: paths.hookState) else { return nil }
        return try? SnapshotStore.decoder.decode(HookState.self, from: data)
    }
}
