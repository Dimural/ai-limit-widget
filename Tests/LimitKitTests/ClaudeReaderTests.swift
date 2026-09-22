import XCTest

@testable import LimitKit

final class ClaudeReaderTests: XCTestCase {
    func testReadsBothWindows() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-two-windows.json"))
        )

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(Set(snapshot.windows.map(\.label)), ["5-hour", "Weekly"])

        let fiveHour = try XCTUnwrap(snapshot.windows.first { $0.label == "5-hour" })
        XCTAssertEqual(fiveHour.usedPercent, 42.5, accuracy: 0.001)
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

    /// Reset times arrive as ISO-8601 in one window and Unix seconds in
    /// another; both must land on the same timeline.
    func testAcceptsBothResetTimestampFormats() throws {
        let snapshot = try XCTUnwrap(
            ClaudeReader.parse(captureFile: try Fixture.data("claude-capture-two-windows.json"))
        )

        let fiveHour = try XCTUnwrap(snapshot.windows.first { $0.label == "5-hour" })
        let weekly = try XCTUnwrap(snapshot.windows.first { $0.label == "Weekly" })

        XCTAssertEqual(
            fiveHour.resetsAt,
            ISO8601DateFormatter().date(from: "2026-09-22T05:00:00Z")
        )
        XCTAssertEqual(weekly.resetsAt, Date(timeIntervalSince1970: 1_790_000_000))
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

        XCTAssertEqual(snapshot.tightestWindow?.label, "5-hour")
    }
}
