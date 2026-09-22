import Foundation

/// Every filesystem location AI Limits touches, in one place.
///
/// `home` is injectable so tests can run against a temporary directory and
/// never see the real `~/.claude` or `~/.codex`.
public struct Paths: Sendable {
    public static let appBundleID = "com.dimural.AILimits"
    public static let widgetBundleID = "com.dimural.AILimits.Widget"

    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    // MARK: - Ours (read/write)

    /// Where the collector and the status line shim keep their state.
    public var appSupport: URL {
        home.appending(path: "Library/Application Support/AILimits", directoryHint: .isDirectory)
    }

    /// Written by the status line shim on every Claude Code render.
    public var claudeSnapshot: URL { appSupport.appending(path: "claude.json") }

    /// Records what `statusLine` looked like before we touched it, so the
    /// uninstaller can put it back exactly.
    public var hookState: URL { appSupport.appending(path: "claude-hook-state.json") }

    /// The merged snapshot the menu bar renders from.
    public var snapshot: URL { appSupport.appending(path: "snapshot.json") }

    /// The same snapshot, pushed into the widget extension's sandbox
    /// container. A sandboxed extension may read files inside its own
    /// container without any entitlement, which is why the collector writes
    /// here instead of relying on an App Group.
    public var widgetContainerSnapshot: URL {
        home
            .appending(path: "Library/Containers/\(Self.widgetBundleID)/Data", directoryHint: .isDirectory)
            .appending(path: "Library/Application Support/AILimits", directoryHint: .isDirectory)
            .appending(path: "snapshot.json")
    }

    /// Where the widget extension itself looks. Inside the sandbox its own
    /// home *is* the container, so this resolves to the path above.
    public var snapshotForWidget: URL {
        home.appending(path: "Library/Application Support/AILimits/snapshot.json")
    }

    // MARK: - Theirs (read-only, except `claudeSettings` during install)

    public var claudeSettings: URL { home.appending(path: ".claude/settings.json") }

    public var claudeSettingsBackup: URL {
        home.appending(path: ".claude/settings.json.ailimits-backup")
    }

    public var codexSessions: URL {
        home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
    }
}
