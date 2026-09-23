import XCTest

@testable import LimitKit

final class SnapshotStoreTests: XCTestCase {
    private func sampleSnapshot() -> Snapshot {
        Snapshot(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            providers: [
                ProviderSnapshot(
                    provider: .codex,
                    planLabel: "plus",
                    windows: [
                        LimitWindow(label: "5-hour", usedPercent: 33, resetsAt: Date(timeIntervalSince1970: 1_790_001_000)),
                        LimitWindow(label: "Weekly", usedPercent: 7, resetsAt: nil),
                    ],
                    sourceUpdatedAt: Date(timeIntervalSince1970: 1_789_999_000)
                )
            ]
        )
    }

    func testRoundTripsThroughDisk() throws {
        let home = try TemporaryHome()
        let store = SnapshotStore()

        try store.write(sampleSnapshot(), to: home.paths.snapshot)
        let loaded = try XCTUnwrap(store.read(from: home.paths.snapshot))

        XCTAssertEqual(loaded, sampleSnapshot())
    }

    /// The snapshot is only ever this user's business.
    func testSnapshotIsWrittenPrivateToTheUser() throws {
        let home = try TemporaryHome()
        try SnapshotStore().write(sampleSnapshot(), to: home.paths.snapshot)

        let attributes = try FileManager.default.attributesOfItem(atPath: home.paths.snapshot.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
    }

    func testMissingAndCorruptFilesReadAsNoData() throws {
        let home = try TemporaryHome()
        let store = SnapshotStore()

        XCTAssertNil(store.read(from: home.paths.snapshot))

        try home.write("{ not json", to: "Library/Application Support/AILimits/snapshot.json")
        XCTAssertNil(store.read(from: home.paths.snapshot))
    }

    /// An older widget must not guess at a newer file's meaning; it shows
    /// "no data" and the user updates.
    func testRefusesAFutureSchemaVersion() throws {
        let home = try TemporaryHome()
        let future = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion + 1,
            generatedAt: Date(),
            providers: []
        )

        try SnapshotStore().write(future, to: home.paths.snapshot)
        XCTAssertNil(SnapshotStore().read(from: home.paths.snapshot))
    }

    /// The widget may read at any moment, so a write must never be observable
    /// half-finished.
    func testOverwritingLeavesNoIntermediateState() throws {
        let home = try TemporaryHome()
        let store = SnapshotStore()

        try store.write(sampleSnapshot(), to: home.paths.snapshot)
        for _ in 0..<20 {
            try store.write(sampleSnapshot(), to: home.paths.snapshot)
            XCTAssertNotNil(store.read(from: home.paths.snapshot))
        }

        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: home.paths.appSupport.path
        ).filter { $0.hasPrefix(".snapshot.json") }
        XCTAssertTrue(leftovers.isEmpty, "Temporary files must not accumulate: \(leftovers)")
    }

    func testCreatesItsDirectoryOnFirstWrite() throws {
        let home = try TemporaryHome()
        XCTAssertFalse(home.exists("Library/Application Support/AILimits"))

        try SnapshotStore().write(sampleSnapshot(), to: home.paths.snapshot)

        XCTAssertTrue(home.exists("Library/Application Support/AILimits/snapshot.json"))
    }
}

final class SnapshotBuilderTests: XCTestCase {
    /// A provider that has never run is absent, not zero. An empty bar would
    /// read as "plenty left", which is the opposite of the truth.
    func testAbsentProvidersAreOmittedRatherThanShownAsEmpty() throws {
        let home = try TemporaryHome()

        let snapshot = SnapshotBuilder(paths: home.paths).build()

        XCTAssertTrue(snapshot.providers.isEmpty)
        XCTAssertNil(snapshot.provider(.claude))
        XCTAssertNil(snapshot.provider(.codex))
    }

    func testCombinesEveryProviderThatHasData() throws {
        let home = try TemporaryHome()
        try home.write(
            String(decoding: try Fixture.data("claude-capture-two-windows.json"), as: UTF8.self),
            to: "Library/Application Support/AILimits/claude.json"
        )
        try home.write(
            try Fixture.lines("codex-both-windows.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2026/09/22/rollout-x.jsonl"
        )

        let snapshot = SnapshotBuilder(paths: home.paths).build()

        XCTAssertEqual(snapshot.providers.count, 2)
        XCTAssertNotNil(snapshot.provider(.claude))
        XCTAssertNotNil(snapshot.provider(.codex))
        XCTAssertEqual(snapshot.schemaVersion, Snapshot.currentSchemaVersion)
    }
}

final class FileTailTests: XCTestCase {
    private func write(_ contents: String, in home: TemporaryHome) throws -> URL {
        try home.write(contents, to: "tail.txt")
        return home.url.appending(path: "tail.txt")
    }

    func testReturnsEveryLineWhenTheFileFitsInTheLimit() throws {
        let home = try TemporaryHome()
        let url = try write("one\ntwo\nthree\n", in: home)

        XCTAssertEqual(try FileTail.lines(of: url), ["one", "two", "three"])
    }

    /// Starting mid-file slices the first line in half, so it is dropped —
    /// and only it. The complete lines after it must all survive.
    func testDiscardsThePartialLineAtTheStartOfTheWindow() throws {
        let home = try TemporaryHome()
        // 21 bytes; the last 12 begin part-way through "aaaaaaaaaa".
        let url = try write("aaaaaaaaaa\nbbbb\ncccc\n", in: home)

        XCTAssertEqual(try FileTail.lines(of: url, byteLimit: 12), ["bbbb", "cccc"])
    }

    func testEmptyFileYieldsNoLines() throws {
        let home = try TemporaryHome()
        let url = try write("", in: home)

        XCTAssertEqual(try FileTail.lines(of: url), [])
    }

    func testMissingFileThrowsRatherThanReturningNothing() throws {
        let home = try TemporaryHome()
        XCTAssertThrowsError(try FileTail.lines(of: home.url.appending(path: "absent.txt")))
    }
}

/// The collector watches the directory it writes into. An unconditional write
/// retriggers the watcher, which writes again — a loop that rewrote the
/// snapshot once a second for as long as the app ran, and burned CPU doing it.
final class RedundantWriteTests: XCTestCase {
    private func snapshot(codexPercent: Double, generatedAt: Date) -> Snapshot {
        Snapshot(
            generatedAt: generatedAt,
            providers: [
                ProviderSnapshot(
                    provider: .codex,
                    planLabel: "plus",
                    windows: [LimitWindow(label: "Weekly", usedPercent: codexPercent, resetsAt: nil)],
                    sourceUpdatedAt: Date(timeIntervalSince1970: 1_790_000_000)
                )
            ]
        )
    }

    func testFirstWriteAlwaysHappens() throws {
        let home = try TemporaryHome()
        let wrote = try SnapshotStore().writeIfChanged(
            snapshot(codexPercent: 4, generatedAt: Date()), to: home.paths.snapshot
        )
        XCTAssertTrue(wrote)
    }

    /// The loop, reproduced: identical data, only the rebuild time differs.
    func testIdenticalDataIsNotRewritten() throws {
        let home = try TemporaryHome()
        let store = SnapshotStore()
        try store.writeIfChanged(
            snapshot(codexPercent: 4, generatedAt: Date(timeIntervalSince1970: 1)),
            to: home.paths.snapshot
        )
        let firstModified = try modificationDate(of: home.paths.snapshot)

        for second in 2...5 {
            let wrote = try store.writeIfChanged(
                snapshot(codexPercent: 4, generatedAt: Date(timeIntervalSince1970: TimeInterval(second))),
                to: home.paths.snapshot
            )
            XCTAssertFalse(wrote, "A rebuild with the same numbers must not touch the file")
        }

        XCTAssertEqual(try modificationDate(of: home.paths.snapshot), firstModified)
    }

    func testRealChangesStillGetWritten() throws {
        let home = try TemporaryHome()
        let store = SnapshotStore()
        try store.writeIfChanged(snapshot(codexPercent: 4, generatedAt: Date()), to: home.paths.snapshot)

        let wrote = try store.writeIfChanged(
            snapshot(codexPercent: 5, generatedAt: Date()), to: home.paths.snapshot
        )

        XCTAssertTrue(wrote)
        XCTAssertEqual(
            store.read(from: home.paths.snapshot)?.providers.first?.windows.first?.usedPercent, 5
        )
    }

    /// A corrupt or truncated file must be replaced, not mistaken for a match.
    func testUnreadableExistingFileIsOverwritten() throws {
        let home = try TemporaryHome()
        try home.write("{ not json", to: "Library/Application Support/AILimits/snapshot.json")

        let wrote = try SnapshotStore().writeIfChanged(
            snapshot(codexPercent: 4, generatedAt: Date()), to: home.paths.snapshot
        )

        XCTAssertTrue(wrote)
    }

    private func modificationDate(of url: URL) throws -> Date {
        try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        )
    }
}

/// Storing a snapshot must not change it. The collector compares what it
/// rebuilt against what is on disk to decide whether anything happened, so any
/// detail lost in encoding turns every rebuild into a spurious change.
final class RoundTripFidelityTests: XCTestCase {
    func testASnapshotBuiltFromRealFixturesSurvivesStorageUnchanged() throws {
        let home = try TemporaryHome()
        try home.write(
            String(decoding: try Fixture.data("claude-capture-two-windows.json"), as: UTF8.self),
            to: "Library/Application Support/AILimits/claude.json"
        )
        // This fixture's event timestamps carry milliseconds, which is exactly
        // what ISO-8601 storage used to discard.
        try home.write(
            try Fixture.lines("codex-both-windows.jsonl").joined(separator: "\n"),
            to: ".codex/sessions/2026/09/22/rollout-x.jsonl"
        )

        let built = SnapshotBuilder(paths: home.paths).build()
        let store = SnapshotStore()
        try store.write(built, to: home.paths.snapshot)

        let loaded = try XCTUnwrap(store.read(from: home.paths.snapshot))
        XCTAssertEqual(loaded.providers, built.providers)

        // And therefore the collector sees no change and does not rewrite.
        XCTAssertFalse(try store.writeIfChanged(built, to: home.paths.snapshot))
    }
}
