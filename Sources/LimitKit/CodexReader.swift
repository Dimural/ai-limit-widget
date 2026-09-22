import Foundation

/// Reads Codex's usage limits from the rollout file it is already writing.
///
/// Codex records a `token_count` event after every turn, and each one carries
/// the server's own `rate_limits` figures:
///
/// ```json
/// {"type":"event_msg","timestamp":"2026-08-05T04:19:41.777Z","payload":{
///   "type":"token_count",
///   "rate_limits":{"primary":{"used_percent":33.0,"window_minutes":300,
///                             "resets_at":1781855290},
///                  "secondary":{"used_percent":7.0,"window_minutes":10080,
///                               "resets_at":1782421690},
///                  "plan_type":"plus"}}}
/// ```
///
/// Codex needs no installation step: this data is on disk the moment Codex
/// runs. We read the tail of the newest rollout file, take the numbers out of
/// the most recent event, and ignore everything else in the file. Conversation
/// content is never parsed, retained, or logged.
public struct CodexReader {
    private let paths: Paths

    public init(paths: Paths = Paths()) {
        self.paths = paths
    }

    /// Returns Codex's current limits, or `nil` when Codex has never run, has
    /// not reported limits yet, or its file format has changed beyond
    /// recognition. A `nil` is displayed as "not connected", never as 0%.
    public func read() -> ProviderSnapshot? {
        guard let rollout = CodexSessionLocator.newestRollout(in: paths.codexSessions) else {
            return nil
        }
        return Self.parse(rolloutLines: (try? FileTail.lines(of: rollout)) ?? [])
    }

    /// Split out from file access so it can be tested against fixtures.
    /// Scans backwards for the newest event that actually carries limits: a
    /// session can end with events that have none, and the last *usable*
    /// reading is what we want.
    public static func parse(rolloutLines lines: [String]) -> ProviderSnapshot? {
        for line in lines.reversed() {
            guard line.contains("rate_limits"),
                  let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any],
                  let snapshot = snapshot(from: limits, eventTimestamp: root["timestamp"])
            else { continue }
            return snapshot
        }
        return nil
    }

    private static func snapshot(
        from limits: [String: Any],
        eventTimestamp: Any?
    ) -> ProviderSnapshot? {
        let windows = ["primary", "secondary"].compactMap { key -> LimitWindow? in
            window(from: limits[key] as? [String: Any])
        }
        guard !windows.isEmpty else { return nil }

        return ProviderSnapshot(
            provider: .codex,
            planLabel: limits["plan_type"] as? String,
            windows: windows,
            sourceUpdatedAt: RateLimitParsing.resetDate(eventTimestamp) ?? Date()
        )
    }

    private static func window(from raw: [String: Any]?) -> LimitWindow? {
        guard let raw,
              let percent = RateLimitParsing.percent(
                  RateLimitParsing.value(raw, "used_percent", "usedPercent")
              )
        else { return nil }

        let minutes = (RateLimitParsing.value(raw, "window_minutes", "windowMinutes")
            as? NSNumber)?.intValue

        return LimitWindow(
            label: minutes.map(RateLimitParsing.label(forWindowMinutes:)) ?? "Usage",
            usedPercent: percent,
            resetsAt: RateLimitParsing.resetDate(
                RateLimitParsing.value(raw, "resets_at", "resetsAt")
            )
        )
    }
}
