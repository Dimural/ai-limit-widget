import XCTest

@testable import LimitKit

final class RateLimitParsingTests: XCTestCase {
    func testReadsUnixSecondsAndMilliseconds() {
        XCTAssertEqual(
            RateLimitParsing.resetDate(1_781_855_290),
            Date(timeIntervalSince1970: 1_781_855_290)
        )
        XCTAssertEqual(
            RateLimitParsing.resetDate(1_781_855_290_000),
            Date(timeIntervalSince1970: 1_781_855_290)
        )
    }

    func testReadsISO8601WithAndWithoutFractionalSeconds() throws {
        let expected = ISO8601DateFormatter().date(from: "2026-08-05T04:19:41Z")
        XCTAssertEqual(RateLimitParsing.resetDate("2026-08-05T04:19:41Z"), expected)

        // Truncated to the second: the snapshot is stored as ISO-8601, which
        // carries no fractional part, so keeping milliseconds would mean a
        // timestamp never equalled its own stored form.
        XCTAssertEqual(RateLimitParsing.resetDate("2026-08-05T04:19:41.777Z"), expected)
        XCTAssertEqual(RateLimitParsing.resetDate(1_781_855_290.9), Date(timeIntervalSince1970: 1_781_855_290))
    }

    func testRejectsUnusableTimestamps() {
        XCTAssertNil(RateLimitParsing.resetDate(nil))
        XCTAssertNil(RateLimitParsing.resetDate(0))
        XCTAssertNil(RateLimitParsing.resetDate("whenever"))
        XCTAssertNil(RateLimitParsing.resetDate(NSNull()))
    }

    func testReadsPercentagesInEveryShapeProvidersUse() {
        XCTAssertEqual(RateLimitParsing.percent(33), 33)
        XCTAssertEqual(RateLimitParsing.percent(4.5), 4.5)
        XCTAssertEqual(RateLimitParsing.percent("12.5"), 12.5)
        XCTAssertNil(RateLimitParsing.percent("lots"))
        XCTAssertNil(RateLimitParsing.percent(nil))
    }

    func testFallsBackToEitherKeySpelling() {
        let dict: [String: Any] = ["usedPercent": 7]
        XCTAssertEqual(RateLimitParsing.percent(
            RateLimitParsing.value(dict, "used_percent", "usedPercent")
        ), 7)
    }

    func testTreatsExplicitNullAsAbsent() {
        let dict: [String: Any] = ["resets_at": NSNull()]
        XCTAssertNil(RateLimitParsing.value(dict, "resets_at"))
    }

    func testNamesTheWindowsPeopleRecognise() {
        XCTAssertEqual(RateLimitParsing.label(forWindowMinutes: 300), "5-hour")
        XCTAssertEqual(RateLimitParsing.label(forWindowMinutes: 10080), "Weekly")
        XCTAssertEqual(RateLimitParsing.label(forWindowMinutes: 1440), "Daily")
    }

    /// A provider introducing a new window length should still produce
    /// something readable rather than being dropped.
    func testDerivesALabelForUnfamiliarWindowLengths() {
        XCTAssertEqual(RateLimitParsing.label(forWindowMinutes: 180), "3-hour")
        XCTAssertEqual(RateLimitParsing.label(forWindowMinutes: 4320), "3-day")
        XCTAssertEqual(RateLimitParsing.label(forWindowMinutes: 20160), "2-week")
        XCTAssertEqual(RateLimitParsing.label(forWindowMinutes: 45), "45-minute")
    }
}

final class LimitWindowTests: XCTestCase {
    /// A provider reporting 103% must not render a bar that overflows its
    /// track, and a negative value must not render an inverted one.
    func testClampsPercentagesToARenderableRange() {
        XCTAssertEqual(LimitWindow(label: "x", usedPercent: 140, resetsAt: nil).usedPercent, 100)
        XCTAssertEqual(LimitWindow(label: "x", usedPercent: -4, resetsAt: nil).usedPercent, 0)
    }

    func testExhaustionIsInclusiveOfExactlyFull() {
        XCTAssertTrue(LimitWindow(label: "x", usedPercent: 100, resetsAt: nil).isExhausted)
        XCTAssertFalse(LimitWindow(label: "x", usedPercent: 99.9, resetsAt: nil).isExhausted)
    }
}

final class PresentationTests: XCTestCase {
    func testSeverityBoundaries() {
        XCTAssertEqual(Presentation.severity(forUsedPercent: 0), .comfortable)
        XCTAssertEqual(Presentation.severity(forUsedPercent: 59.9), .comfortable)
        XCTAssertEqual(Presentation.severity(forUsedPercent: 60), .warning)
        XCTAssertEqual(Presentation.severity(forUsedPercent: 84.9), .warning)
        XCTAssertEqual(Presentation.severity(forUsedPercent: 85), .critical)
        XCTAssertEqual(Presentation.severity(forUsedPercent: 99.9), .critical)
        XCTAssertEqual(Presentation.severity(forUsedPercent: 100), .exhausted)
    }

    func testCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Presentation.compactCountdown(until: now.addingTimeInterval(8100), from: now), "2h 15m")
        XCTAssertEqual(Presentation.compactCountdown(until: now.addingTimeInterval(900), from: now), "15m")
        XCTAssertEqual(Presentation.compactCountdown(until: now.addingTimeInterval(180_000), from: now), "2d 2h")
    }

    /// A window that has already reset while the collector was asleep must not
    /// render a negative countdown.
    func testCountdownInThePastReadsAsNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Presentation.compactCountdown(until: now.addingTimeInterval(-60), from: now), "now")
    }

    /// "resets in now" is nonsense, and an allowance past its reset time is
    /// rolling over rather than counting down to anything.
    func testResetPhrasing() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func window(_ offset: TimeInterval?) -> LimitWindow {
            LimitWindow(
                label: "5-hour", usedPercent: 50,
                resetsAt: offset.map { now.addingTimeInterval($0) }
            )
        }

        XCTAssertEqual(Presentation.resetPhrase(for: window(8100), asOf: now), "resets in 2h 15m")
        XCTAssertEqual(Presentation.resetPhrase(for: window(-60), asOf: now), "resetting now")
        XCTAssertEqual(Presentation.resetPhrase(for: window(0), asOf: now), "resetting now")
        XCTAssertEqual(
            Presentation.resetPhrase(for: window(nil), asOf: now), "no reset time reported"
        )
    }

    /// The menu bar and the widget build their colours from these numbers, so
    /// a reading can never look one way in one place and another elsewhere.
    func testEverySeverityHasADistinctInk() {
        let inks = Presentation.Severity.allSeverities.map(Presentation.ink(for:))
        XCTAssertEqual(Set(inks).count, inks.count)
    }

    /// Dark backgrounds wash out the deeper tones, so each is lifted — but
    /// lifting must not push a colour out of range.
    func testLiftedInksStayInRange() {
        for severity in Presentation.Severity.allSeverities {
            let lifted = Presentation.ink(for: severity).lifted
            for channel in [lifted.red, lifted.green, lifted.blue] {
                XCTAssertTrue((0...1).contains(channel), "\(severity) lifted out of range")
            }
        }
    }

    func testStalenessIsMeasuredFromTheProvidersOwnTimestamp() {
        let snapshot = ProviderSnapshot(
            provider: .claude,
            planLabel: nil,
            windows: [LimitWindow(label: "5-hour", usedPercent: 10, resetsAt: nil)],
            sourceUpdatedAt: Date(timeIntervalSince1970: 1_000_000)
        )

        XCTAssertFalse(snapshot.isStale(
            asOf: Date(timeIntervalSince1970: 1_000_000 + 60),
            threshold: Presentation.stalenessThreshold
        ))
        XCTAssertTrue(snapshot.isStale(
            asOf: Date(timeIntervalSince1970: 1_000_000 + 3600),
            threshold: Presentation.stalenessThreshold
        ))
    }
}
