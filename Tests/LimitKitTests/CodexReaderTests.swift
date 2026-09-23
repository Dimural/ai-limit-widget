import XCTest

@testable import LimitKit

final class CodexReaderTests: XCTestCase {
    func testReadsBothWindowsFromRealRollout() throws {
        let snapshot = try XCTUnwrap(
            CodexReader.parse(rolloutLines: Fixture.lines("codex-both-windows.jsonl"))
        )

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.planLabel, "plus")
        XCTAssertEqual(Set(snapshot.windows.map(\.label)), ["5-hour", "Weekly"])

        let fiveHour = try XCTUnwrap(snapshot.windows.first { $0.label == "5-hour" })
        XCTAssertEqual(fiveHour.usedPercent, 33, accuracy: 0.001)
        XCTAssertEqual(fiveHour.resetsAt, Date(timeIntervalSince1970: 1_781_855_290))
    }

    /// Codex reports only a weekly window on some plans; the 5-hour slot
    /// arrives as an explicit null and must not become a phantom 0% bar.
    func testOmitsNullSecondaryWindow() throws {
        let snapshot = try XCTUnwrap(
            CodexReader.parse(rolloutLines: Fixture.lines("codex-single-window.jsonl"))
        )

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].label, "Weekly")
    }

    /// The tail of a live rollout file usually ends mid-write. The partial
    /// line must be skipped in favour of the last complete one, not crash the
    /// reader or produce nothing.
    func testSkipsTruncatedFinalLine() throws {
        let snapshot = try XCTUnwrap(
            CodexReader.parse(rolloutLines: Fixture.lines("codex-truncated-last-line.jsonl"))
        )

        XCTAssertEqual(snapshot.windows.count, 2)
    }

    func testReturnsNilWhenNoEventCarriesLimits() throws {
        let lines = try Fixture.lines("codex-no-rate-limits.jsonl")
        XCTAssertNil(CodexReader.parse(rolloutLines: lines))
    }

    func testReturnsNilForEmptyAndUnparseableInput() {
        XCTAssertNil(CodexReader.parse(rolloutLines: []))
        XCTAssertNil(CodexReader.parse(rolloutLines: ["not json at all"]))
        XCTAssertNil(CodexReader.parse(rolloutLines: [#"{"payload":{"rate_limits":"nonsense"}}"#]))
    }

    /// Sessions end with events that carry no limits. The newest *usable*
    /// reading is the one to show, not the newest event.
    func testPrefersMostRecentLineThatCarriesLimits() throws {
        var lines = try Fixture.lines("codex-both-windows.jsonl")
        lines.append(contentsOf: try Fixture.lines("codex-no-rate-limits.jsonl"))

        let snapshot = try XCTUnwrap(CodexReader.parse(rolloutLines: lines))
        XCTAssertEqual(snapshot.windows.count, 2)
    }

    func testNoCodexInstallationReadsAsNotConnected() throws {
        let home = try TemporaryHome()
        XCTAssertNil(CodexReader(paths: home.paths).read())
    }

    func testReadsThroughTheRealDirectoryLayout() throws {
        let home = try TemporaryHome()
        let line = try Fixture.lines("codex-both-windows.jsonl").joined(separator: "\n")
        try home.write(line, to: ".codex/sessions/2026/09/22/rollout-2026-09-22T01-00-00-abc.jsonl")

        let snapshot = try XCTUnwrap(CodexReader(paths: home.paths).read())
        XCTAssertEqual(snapshot.windows.count, 2)
    }

    /// Only the newest dated directory should be consulted, even when older
    /// ones are still present.
    func testPicksNewestDatedDirectory() throws {
        let home = try TemporaryHome()
        try home.write(
            try Fixture.lines("codex-single-window.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2025/01/02/rollout-old.jsonl"
        )
        try home.write(
            try Fixture.lines("codex-both-windows.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2026/09/22/rollout-new.jsonl"
        )

        let snapshot = try XCTUnwrap(CodexReader(paths: home.paths).read())
        XCTAssertEqual(snapshot.windows.count, 2, "Should have read the 2026 session, not the 2025 one")
    }
}
