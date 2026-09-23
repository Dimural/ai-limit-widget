import Foundation

/// Shared, deliberately forgiving helpers for reading provider JSON.
///
/// These formats belong to third parties and change without notice, so every
/// helper returns `nil` rather than throwing: a field we cannot understand
/// means one window is missing, never a crashed collector or a broken status
/// line. Anything genuinely unparseable is simply not displayed.
public enum RateLimitParsing {
    /// Accepts either spelling of a key, so a provider renaming
    /// `used_percent` to `usedPercent` does not silently zero the display.
    public static func value(_ dict: [String: Any], _ keys: String...) -> Any? {
        for key in keys {
            if let found = dict[key], !(found is NSNull) { return found }
        }
        return nil
    }

    /// Reads a percentage that may arrive as an Int, a Double, or a numeric
    /// string. Out-of-range values are clamped by `LimitWindow`.
    public static func percent(_ raw: Any?) -> Double? {
        switch raw {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    /// Reads a reset timestamp in any of the shapes providers actually use:
    /// Unix seconds, Unix milliseconds, or an ISO-8601 string.
    ///
    /// Results are truncated to whole seconds. Usage windows reset on minute
    /// boundaries, so sub-second precision means nothing here — and keeping it
    /// actively breaks things: the snapshot is stored as ISO-8601, which has
    /// no fractional part, so a timestamp carrying milliseconds would never
    /// compare equal to its own stored form. The collector used that
    /// comparison to decide whether anything had changed, and so rewrote the
    /// snapshot every second forever.
    ///
    /// Values are disambiguated by magnitude: anything at or beyond
    /// `millisecondThreshold` is treated as milliseconds. That boundary sits
    /// far past any plausible seconds-based reset date, so a seconds value can
    /// never be misread as milliseconds.
    public static func resetDate(_ raw: Any?) -> Date? {
        let millisecondThreshold = 100_000_000_000.0  // ~year 5138 in seconds

        switch raw {
        case let number as NSNumber:
            let value = number.doubleValue
            guard value > 0 else { return nil }
            let seconds = value >= millisecondThreshold ? value / 1000 : value
            return Date(timeIntervalSince1970: seconds.rounded(.down))
        case let string as String:
            if let value = Double(string) {
                return resetDate(NSNumber(value: value))
            }
            let parsed = isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
            return parsed.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
        default:
            return nil
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Turns a window duration into the label people actually use for it.
    /// Unknown durations fall back to a rounded hour or day count rather than
    /// being dropped, so a provider adding a new window still displays.
    public static func label(forWindowMinutes minutes: Int) -> String {
        switch minutes {
        case 300: return "5-hour"
        case 10080: return "Weekly"
        case 1440: return "Daily"
        case 60: return "Hourly"
        default:
            if minutes % 10080 == 0 { return "\(minutes / 10080)-week" }
            if minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
            if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
            return "\(minutes)-minute"
        }
    }
}
