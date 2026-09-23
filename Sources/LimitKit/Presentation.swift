import Foundation

/// Display rules shared by the menu bar and the widget, so the two can never
/// disagree about what "nearly out" looks like.
public enum Presentation {
    /// Claude Code only reports limits while a session is open, so its numbers
    /// go stale as a matter of course. Past this age the UI says when it last
    /// heard anything, rather than presenting the figure as current.
    ///
    /// It says so in words, not by fading the card out: a dimmed reading
    /// looks like a broken one, and these readings are not broken — they are
    /// simply from a known moment.
    public static let stalenessThreshold: TimeInterval = 15 * 60

    /// Where a bar's warning notch sits. Marking it turns the bar into an
    /// instrument with a scale, rather than a strip that happens to change
    /// colour: you can see how close you are to trouble without reading the
    /// number.
    public static let criticalThreshold: Double = 85

    public enum Severity: String, Sendable, CaseIterable {
        case comfortable   // plenty of headroom
        case warning       // worth knowing about
        case critical      // nearly out
        case exhausted     // requests are being refused

        public static let allSeverities = Severity.allCases

        /// The UI layers length, position against the notch, and the number
        /// itself on top of colour, rather than relying on hue alone.
        public var sortOrder: Int {
            switch self {
            case .comfortable: return 0
            case .warning: return 1
            case .critical: return 2
            case .exhausted: return 3
            }
        }
    }

    /// The colour of a reading, as plain components so AppKit and SwiftUI
    /// build their own colours from identical numbers and cannot drift apart.
    ///
    /// Not one accent colour applied to everything: the colour *is* the
    /// reading. It walks from spruce through ochre to a burnt red as the
    /// allowance goes, and each step is dark enough to hold its own against
    /// both a light and a dark desktop.
    public struct Ink: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        /// A lighter cast for dark backgrounds, where the deep tones lose
        /// their separation.
        public var lifted: Ink {
            Ink(
                red: red + (1 - red) * 0.22,
                green: green + (1 - green) * 0.22,
                blue: blue + (1 - blue) * 0.22
            )
        }
    }

    public static func ink(for severity: Severity) -> Ink {
        switch severity {
        case .comfortable: return Ink(red: 0.18, green: 0.62, blue: 0.48)  // spruce
        case .warning: return Ink(red: 0.79, green: 0.64, blue: 0.15)      // ochre
        case .critical: return Ink(red: 0.82, green: 0.33, blue: 0.17)     // burnt orange
        case .exhausted: return Ink(red: 0.75, green: 0.22, blue: 0.17)    // deep red
        }
    }

    public static func severity(forUsedPercent percent: Double) -> Severity {
        switch percent {
        case ..<60: return .comfortable
        case ..<criticalThreshold: return .warning
        case ..<100: return .critical
        default: return .exhausted
        }
    }

    /// How a window's reset reads in a sentence.
    ///
    /// A window already past its reset says so plainly: "resets in now" is
    /// nonsense, and the allowance is rolling over rather than counting down.
    public static func resetPhrase(for window: LimitWindow, asOf now: Date = Date()) -> String {
        guard let resetsAt = window.resetsAt else { return "no reset time reported" }
        guard !window.hasReset(asOf: now) else { return "resetting now" }
        return "resets in \(compactCountdown(until: resetsAt, from: now))"
    }

    /// "2h 14m", "14m", "now". Deliberately coarse: the widget renders a live
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
