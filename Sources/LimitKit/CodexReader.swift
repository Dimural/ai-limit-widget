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
    /// How far back to look for allowances.
    ///
    /// Codex's longest window is a week. An allowance last touched before
    /// then has already rolled over, so its percentage describes a window
    /// that no longer exists. The extra day is slack for clock differences.
    public static let maxAllowanceAge: TimeInterval = 8 * 24 * 60 * 60

    private let paths: Paths

    public init(paths: Paths = Paths()) {
        self.paths = paths
    }

    /// Every Codex allowance with something current to say — the main one,
    /// plus any per-model limits such as GPT-5.3-Codex-Spark.
    ///
    /// Empty when Codex has never run, has not reported limits yet, or has
    /// not run recently enough for any allowance to still be live. Empty is
    /// displayed as "not connected", never as 0%.
    public func read(now: Date = Date()) -> [ProviderSnapshot] {
        let rollouts = CodexSessionLocator.recentRollouts(
            in: paths.codexSessions,
            modifiedSince: now.addingTimeInterval(-Self.maxAllowanceAge)
        )

        // Newest file first, so the first reading of an allowance is its most
        // recent one and later files cannot overwrite it with older numbers.
        var byBucket: [String: ProviderSnapshot] = [:]
        for rollout in rollouts {
            let lines = (try? FileTail.lines(of: rollout)) ?? []
            for (bucket, snapshot) in Self.parse(rolloutLines: lines) where byBucket[bucket] == nil {
                byBucket[bucket] = snapshot
            }
        }

        return byBucket.values
            .filter { !$0.hasOnlyExpiredWindows(asOf: now) }
            .sorted { $0.id < $1.id }
    }

    /// Split out from file access so it can be tested against fixtures.
    ///
    /// Returns the newest reading of each allowance in these lines, keyed by
    /// Codex's own `limit_id`. Scanning backwards means the first reading of
    /// an allowance is its latest: a session can end with events carrying no
    /// limits at all, and the last *usable* reading is what we want.
    public static func parse(rolloutLines lines: [String]) -> [String: ProviderSnapshot] {
        var byBucket: [String: ProviderSnapshot] = [:]

        for line in lines.reversed() {
            guard line.contains("rate_limits"),
                  let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any]
            else { continue }

            // Codex omits limit_id on older versions, where there is only one
            // allowance to speak of.
            let bucket = limits["limit_id"] as? String ?? "codex"
            guard byBucket[bucket] == nil,
                  let snapshot = snapshot(from: limits, eventTimestamp: root["timestamp"])
            else { continue }
            byBucket[bucket] = snapshot
        }

        return byBucket
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
            // limit_name is Codex's own display name for a per-model
            // allowance. Its absence means the main one.
            bucketName: limits["limit_name"] as? String,
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
