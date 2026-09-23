import XCTest

@testable import LimitKit

final class CodexReaderTests: XCTestCase {
    /// Earlier than the soonest reset across every fixture — the named
    /// allowance's 5-hour window, at 1772439859 — so nothing reads as expired
    /// and the expiry filter is not what these tests are measuring.
    private let whileWindowsAreLive = Date(timeIntervalSince1970: 1_772_400_000)

    private func onlyAllowance(in lines: [String]) throws -> ProviderSnapshot {
        let byBucket = CodexReader.parse(rolloutLines: lines)
        XCTAssertEqual(byBucket.count, 1)
        return try XCTUnwrap(byBucket.values.first)
    }

    func testReadsBothWindowsFromRealRollout() throws {
        let snapshot = try onlyAllowance(in: try Fixture.lines("codex-both-windows.jsonl"))

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.planLabel, "plus")
        XCTAssertEqual(Set(snapshot.windows.map(\.label)), ["5-hour", "Weekly"])

        // The fixture's three events read 9%, 9%, then 10%: the newest wins.
        let fiveHour = try XCTUnwrap(snapshot.windows.first { $0.label == "5-hour" })
        XCTAssertEqual(fiveHour.usedPercent, 10, accuracy: 0.001)
        XCTAssertEqual(fiveHour.resetsAt, Date(timeIntervalSince1970: 1_783_368_283))

        let weekly = try XCTUnwrap(snapshot.windows.first { $0.label == "Weekly" })
        XCTAssertEqual(weekly.usedPercent, 2, accuracy: 0.001)
    }

    /// Codex reports only a weekly window on some plans; the 5-hour slot
    /// arrives as an explicit null and must not become a phantom 0% bar.
    func testOmitsNullSecondaryWindow() throws {
        let snapshot = try onlyAllowance(in: try Fixture.lines("codex-single-window.jsonl"))

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].label, "Weekly")
    }

    /// The tail of a live rollout file usually ends mid-write. The partial
    /// line must be skipped in favour of the last complete one, not crash the
    /// reader or produce nothing.
    func testSkipsTruncatedFinalLine() throws {
        let snapshot = try onlyAllowance(in: try Fixture.lines("codex-truncated-last-line.jsonl"))

        XCTAssertEqual(snapshot.windows.count, 2)
    }

    func testReturnsNothingWhenNoEventCarriesLimits() throws {
        let lines = try Fixture.lines("codex-no-rate-limits.jsonl")
        XCTAssertTrue(CodexReader.parse(rolloutLines: lines).isEmpty)
    }

    func testReturnsNothingForEmptyAndUnparseableInput() {
        XCTAssertTrue(CodexReader.parse(rolloutLines: []).isEmpty)
        XCTAssertTrue(CodexReader.parse(rolloutLines: ["not json at all"]).isEmpty)
        XCTAssertTrue(
            CodexReader.parse(rolloutLines: [#"{"payload":{"rate_limits":"nonsense"}}"#]).isEmpty
        )
    }

    /// Sessions end with events that carry no limits. The newest *usable*
    /// reading is the one to show, not the newest event.
    func testPrefersMostRecentLineThatCarriesLimits() throws {
        var lines = try Fixture.lines("codex-both-windows.jsonl")
        lines.append(contentsOf: try Fixture.lines("codex-no-rate-limits.jsonl"))

        XCTAssertEqual(try onlyAllowance(in: lines).windows.count, 2)
    }

    // MARK: - Named allowances

    /// Codex tracks some models separately — GPT-5.3-Codex-Spark has its own
    /// windows, which used to be discarded because only one reading survived.
    func testReadsAPerModelAllowanceUnderItsOwnName() throws {
        let snapshot = try onlyAllowance(in: try Fixture.lines("codex-named-bucket.jsonl"))

        XCTAssertEqual(snapshot.bucketName, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot.title, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot.windows.count, 2)
    }

    func testTheMainAllowanceHasNoBucketName() throws {
        let snapshot = try onlyAllowance(in: try Fixture.lines("codex-both-windows.jsonl"))

        XCTAssertNil(snapshot.bucketName)
        XCTAssertEqual(snapshot.title, "Codex")
    }

    /// Two allowances in one file must both survive, keyed separately.
    func testKeepsEveryAllowanceApart() throws {
        var lines = try Fixture.lines("codex-both-windows.jsonl")
        lines.append(contentsOf: try Fixture.lines("codex-named-bucket.jsonl"))

        let byBucket = CodexReader.parse(rolloutLines: lines)

        XCTAssertEqual(Set(byBucket.keys), ["codex", "codex_bengalfox"])
        XCTAssertNil(byBucket["codex"]?.bucketName)
        XCTAssertEqual(byBucket["codex_bengalfox"]?.bucketName, "GPT-5.3-Codex-Spark")
    }

    /// Allowances live in separate session files, so finding them all means
    /// reading more than the newest one.
    func testCollectsAllowancesAcrossSessionFiles() throws {
        let home = try TemporaryHome()
        try home.write(
            try Fixture.lines("codex-both-windows.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2026/07/05/rollout-main.jsonl"
        )
        try home.write(
            try Fixture.lines("codex-named-bucket.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2026/07/06/rollout-spark.jsonl"
        )

        let allowances = CodexReader(paths: home.paths).read(now: whileWindowsAreLive)

        XCTAssertEqual(allowances.map(\.title).sorted(), ["Codex", "GPT-5.3-Codex-Spark"])
    }

    // MARK: - Files and freshness

    func testNoCodexInstallationReadsAsNotConnected() throws {
        let home = try TemporaryHome()
        XCTAssertTrue(CodexReader(paths: home.paths).read().isEmpty)
    }

    func testReadsThroughTheRealDirectoryLayout() throws {
        let home = try TemporaryHome()
        try home.write(
            try Fixture.lines("codex-both-windows.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2026/09/22/rollout-2026-09-22T01-00-00-abc.jsonl"
        )

        let allowances = CodexReader(paths: home.paths).read(now: whileWindowsAreLive)
        XCTAssertEqual(allowances.first?.windows.count, 2)
    }

    /// An allowance whose windows have all rolled over describes a window
    /// that no longer exists. Reporting nothing is the truthful answer.
    func testAllowancesWhoseWindowsHaveAllResetAreDropped() throws {
        let home = try TemporaryHome()
        try home.write(
            try Fixture.lines("codex-both-windows.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2026/09/22/rollout-old.jsonl"
        )

        // Long after every window in the fixture has reset.
        let allowances = CodexReader(paths: home.paths).read(
            now: Date(timeIntervalSince1970: 1_790_000_000)
        )

        XCTAssertTrue(allowances.isEmpty)
    }
}
