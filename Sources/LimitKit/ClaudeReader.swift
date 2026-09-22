import Foundation

/// Reads Claude Code's usage limits from the file written by the status line
/// shim (see `Sources/StatusLineShim`).
///
/// Claude Code keeps no live limit snapshot on disk. The one place it hands
/// out its real, server-side figures without credentials or network access is
/// the `rate_limits` object it passes to a configured status line command. The
/// shim captures that object; this reader interprets it.
///
/// Window keys are discovered rather than hard-coded. Claude Code adds and
/// removes windows over time — model-specific weekly limits come and go with
/// the plan — so anything shaped like a window is displayed, and unknown keys
/// get a humanised label instead of being dropped.
public struct ClaudeReader {
    private let paths: Paths

    public init(paths: Paths = Paths()) {
        self.paths = paths
    }

    /// Returns Claude Code's most recently captured limits, or `nil` when the
    /// status line hook has never run. `nil` is displayed as "not connected",
    /// never as 0%.
    public func read() -> ProviderSnapshot? {
        guard let data = try? Data(contentsOf: paths.claudeSnapshot) else { return nil }
        return Self.parse(captureFile: data)
    }

    /// Split out from file access so it can be tested against fixtures.
    public static func parse(captureFile data: Data) -> ProviderSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = RateLimitParsing.value(root, "rateLimits", "rate_limits")
                  as? [String: Any]
        else { return nil }

        let windows = limits
            .compactMap { key, value in window(named: key, from: value as? [String: Any]) }
            .sorted { $0.label < $1.label }
        guard !windows.isEmpty else { return nil }

        let captured = RateLimitParsing.resetDate(
            RateLimitParsing.value(root, "capturedAt", "captured_at")
        )

        return ProviderSnapshot(
            provider: .claude,
            planLabel: RateLimitParsing.value(root, "planLabel", "plan_label") as? String,
            windows: windows,
            sourceUpdatedAt: captured ?? Date()
        )
    }

    /// Labels for the windows Claude Code ships today. Anything else is
    /// humanised from its key, so a newly introduced window still appears.
    private static let knownLabels = [
        "five_hour": "5-hour",
        "seven_day": "Weekly",
        "seven_day_opus": "Weekly (Opus)",
        "seven_day_oauth_apps": "Weekly (apps)",
        "spend_limit": "Spend",
    ]

    private static func window(named key: String, from raw: [String: Any]?) -> LimitWindow? {
        guard let raw,
              let percent = RateLimitParsing.percent(
                  RateLimitParsing.value(raw, "used_percentage", "usedPercentage",
                                         "used_percent", "usedPercent")
              )
        else { return nil }

        return LimitWindow(
            label: knownLabels[key] ?? humanise(key),
            usedPercent: percent,
            resetsAt: RateLimitParsing.resetDate(
                RateLimitParsing.value(raw, "resets_at", "resetsAt")
            )
        )
    }

    /// `seven_day_sonnet` -> `Seven day sonnet`. Ugly beats invisible.
    private static func humanise(_ key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
