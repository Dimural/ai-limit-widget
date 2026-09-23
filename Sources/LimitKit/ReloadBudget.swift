import Foundation

/// Decides when the widget may be reloaded.
///
/// WidgetKit budgets how often a widget can reload, and a busy Codex session
/// can produce several changes a minute. Spending the budget early means the
/// widget stops updating later, which is worse than updating slightly less
/// often — so reloads are spaced out, and the last change in a burst is
/// deferred rather than dropped.
///
/// Kept here, and free of timers, so the rule can be tested rather than
/// observed.
public struct ReloadBudget {
    public enum Decision: Equatable {
        /// Reload now.
        case reloadNow
        /// Too soon. Ask again after this many seconds.
        case retryAfter(TimeInterval)
        /// Too soon, and a retry is already pending — do nothing.
        case alreadyPending
    }

    private let minimumInterval: TimeInterval
    private var lastReload: Date
    private var retryPending = false

    public init(minimumInterval: TimeInterval = 60) {
        self.minimumInterval = minimumInterval
        // distantPast so the first change is never delayed.
        self.lastReload = .distantPast
    }

    public mutating func requestReload(at now: Date = Date()) -> Decision {
        let elapsed = now.timeIntervalSince(lastReload)
        guard elapsed >= minimumInterval else {
            guard !retryPending else { return .alreadyPending }
            retryPending = true
            return .retryAfter(minimumInterval - elapsed)
        }

        lastReload = now
        retryPending = false
        return .reloadNow
    }

    /// Called when a deferred retry comes due, so the next request is judged
    /// fresh rather than being told a retry is still outstanding.
    public mutating func retryCameDue() {
        retryPending = false
    }
}
