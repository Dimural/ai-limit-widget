import Foundation

/// Display rules shared by the menu bar and the widget, so the two can never
/// disagree about what "nearly out" looks like.
public enum Presentation {
    /// Claude Code only reports limits while a session is open, so its numbers
    /// go stale as a matter of course. Past this age the UI dims the card and
    /// labels it "as of …" instead of presenting the figure as current.
    public static let stalenessThreshold: TimeInterval = 15 * 60

    public enum Severity: String, Sendable {
        case comfortable   // plenty of headroom
        case warning       // worth knowing about
        case critical      // nearly out
        case exhausted     // requests are being refused

        /// SF Symbol-free, colour-blind-safe ordering; the UI layers shape and
        /// text on top of colour rather than relying on hue alone.
        public var sortOrder: Int {
            switch self {
            case .comfortable: return 0
            case .warning: return 1
            case .critical: return 2
            case .exhausted: return 3
            }
        }
    }

    public static func severity(forUsedPercent percent: Double) -> Severity {
        switch percent {
        case ..<60: return .comfortable
        case ..<85: return .warning
        case ..<100: return .critical
        default: return .exhausted
        }
    }

    /// "2h 14m", "14m", "Now". Deliberately coarse: the widget renders a live
    /// ticking countdown, and this is for the menu bar, where a second-by-second
    /// number would be noise.
    public static func compactCountdown(until date: Date, from now: Date = Date()) -> String {
        let remaining = Int(date.timeIntervalSince(now))
        guard remaining > 0 else { return "now" }

        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
