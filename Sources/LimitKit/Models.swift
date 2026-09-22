import Foundation

/// An AI CLI whose usage limits AI Limits can display.
public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// A single rate-limit window reported by a provider, such as Claude Code's
/// 5-hour session window or Codex's weekly window.
///
/// `usedPercent` is always the provider's own figure, never something we
/// compute — if a provider does not report a percentage, it gets no window.
public struct LimitWindow: Codable, Hashable, Sendable {
    /// Human-readable window name, e.g. "5-hour" or "Weekly".
    public let label: String
    /// Percentage of the window consumed, 0...100 (clamped on parse).
    public let usedPercent: Double
    /// When the window rolls over, if the provider reported it.
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    /// True once the provider says the window is fully consumed.
    public var isExhausted: Bool { usedPercent >= 100 }
}

/// Everything AI Limits knows about one provider at a point in time.
///
/// This is the *only* data that leaves a reader. No prompts, file paths,
/// account identifiers, or tokens are ever carried in this type.
public struct ProviderSnapshot: Codable, Hashable, Sendable {
    public let provider: ProviderID
    /// Subscription tier as the provider names it ("plus", "max"), when known.
    public let planLabel: String?
    /// Windows in the order they should be displayed, tightest first.
    public let windows: [LimitWindow]
    /// When the *provider* produced these numbers — not when we read them.
    /// Staleness is measured from this, so an idle CLI reads as stale rather
    /// than as fresh-but-unchanged.
    public let sourceUpdatedAt: Date

    public init(
        provider: ProviderID,
        planLabel: String?,
        windows: [LimitWindow],
        sourceUpdatedAt: Date
    ) {
        self.provider = provider
        self.planLabel = planLabel
        // Tightest first, so the window about to stop the user working
        // leads every display. Label breaks ties, so two windows at the same
        // percentage keep a stable order instead of flickering between renders.
        self.windows = windows.sorted {
            $0.usedPercent == $1.usedPercent
                ? $0.label < $1.label
                : $0.usedPercent > $1.usedPercent
        }
        self.sourceUpdatedAt = sourceUpdatedAt
    }

    /// The window closest to being exhausted, which is what the menu bar and
    /// the small widget lead with.
    public var tightestWindow: LimitWindow? { windows.first }

    /// True when any window is fully consumed, i.e. requests are being refused.
    public var isLimitReached: Bool { windows.contains(where: \.isExhausted) }

    /// Data older than `threshold` is shown dimmed and labelled "as of …"
    /// rather than presented as current.
    public func isStale(asOf now: Date = Date(), threshold: TimeInterval) -> Bool {
        now.timeIntervalSince(sourceUpdatedAt) > threshold
    }
}

/// The complete payload written to disk for the widget to render.
public struct Snapshot: Codable, Hashable, Sendable {
    /// Bumped when the on-disk shape changes incompatibly. A widget reading a
    /// version it does not recognise renders "update AI Limits" instead of
    /// guessing at the contents.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// When the collector assembled this file.
    public let generatedAt: Date
    public let providers: [ProviderSnapshot]

    public init(
        schemaVersion: Int = Snapshot.currentSchemaVersion,
        generatedAt: Date,
        providers: [ProviderSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.providers = providers
    }

    public func provider(_ id: ProviderID) -> ProviderSnapshot? {
        providers.first { $0.provider == id }
    }
}
