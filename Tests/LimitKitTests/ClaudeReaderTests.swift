import XCTest

@testable import LimitKit

/// `claude-capture-two-windows.json` is a payload captured from a live Claude
/// Code session, so these tests assert against the shape Claude Code really
/// emits rather than one derived from documentation.
final class ClaudeReaderTests: XCTestCase {
    func testReadsBothWindows() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-two-windows.json"))
        )

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(Set(snapshot.windows.map(\.label)), ["5-hour", "Weekly"])

        let fiveHour = try XCTUnwrap(snapshot.windows.first { $0.label == "5-hour" })
        XCTAssertEqual(fiveHour.usedPercent, 29, accuracy: 0.001)

        let weekly = try XCTUnwrap(snapshot.windows.first { $0.label == "Weekly" })
        XCTAssertEqual(weekly.usedPercent, 5, accuracy: 0.001)
    }

    /// The capture records when it was taken, and staleness is measured from
    /// it — not from when the widget happened to read the file.
    func testTakesItsTimestampFromTheCapture() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-two-windows.json"))
        )

        XCTAssertEqual(
            snapshot.sourceUpdatedAt,
            ISO8601DateFormatter().date(from: "2026-09-23T00:08:02Z")
        )
    }

    /// Claude Code adds and removes windows as plans change. An unrecognised
    /// one must still be displayed, with a readable label, rather than dropped.
    func testDisplaysUnknownWindowKinds() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-unknown-window.json"))
        )

        XCTAssertEqual(snapshot.windows.map(\.label), ["Seven day sonnet"])
        XCTAssertEqual(snapshot.windows[0].usedPercent, 3.25, accuracy: 0.001)
    }

    /// Claude Code sends Unix seconds today. The parser also accepts ISO-8601
    /// so that a change of format costs nothing, which is cheap insurance on a
    /// third-party payload we do not control.
    func testAcceptsUnixResetTimestamps() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-two-windows.json"))
        )

        let fiveHour = try XCTUnwrap(snapshot.windows.first { $0.label == "5-hour" })
        XCTAssertEqual(fiveHour.resetsAt, Date(timeIntervalSince1970: 1_790_137_800))
    }

    func testAcceptsISO8601ResetTimestamps() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-iso-timestamps.json"))
        )

        XCTAssertEqual(
            snapshot.windows.first?.resetsAt,
            ISO8601DateFormatter().date(from: "2026-09-22T05:00:00Z")
        )
    }

    func testFlagsAnExhaustedWindow() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-exhausted.json"))
        )

        XCTAssertTrue(snapshot.isLimitReached)
        XCTAssertTrue(try XCTUnwrap(snapshot.tightestWindow).isExhausted)
    }

    func testReturnsNilWhenCaptureCarriesNoLimits() throws {
        XCTAssertNil(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-no-limits.json"))
        )
    }

    func testReturnsNilForUnparseableInput() {
        XCTAssertNil(ClaudeReader.parse(captureFile: Data()))
        XCTAssertNil(ClaudeReader.parse(captureFile: Data("not json".utf8)))
    }

    func testMissingCaptureFileReadsAsNotConnected() throws {
        let home = try TemporaryHome()
        XCTAssertNil(ClaudeReader(paths: home.paths).read())
    }

    func testReadsFromTheCaptureFileOnDisk() throws {
        let home = try TemporaryHome()
        try home.write(
            String(decoding: try Fixture.data("claude-capture-two-windows.json"), as: UTF8.self),
            to: "Library/Application Support/AILimits/claude.json"
        )

        let snapshot = try XCTUnwrap(ClaudeReader(paths: home.paths).read())
        XCTAssertEqual(snapshot.windows.count, 2)
    }

    /// The tightest window leads the display, because that is the one about to
    /// stop the user working.
    func testTightestWindowLeads() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-two-windows.json"))
        )

        XCTAssertEqual(snapshot.tightestWindow?.label, "5-hour")  // 29% vs 5%
    }
}
