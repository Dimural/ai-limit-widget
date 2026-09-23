import Foundation

/// Assembles one `Snapshot` from every provider that currently has data.
///
/// Providers that have never run, or that have not reported limits yet, are
/// simply absent. They are shown as "not connected" rather than as 0% used,
/// because an empty bar reads as "plenty left" and that would be a lie.
public struct SnapshotBuilder {
    private let claude: ClaudeReader
    private let codex: CodexReader

    public init(paths: Paths = Paths()) {
        self.claude = ClaudeReader(paths: paths)
        self.codex = CodexReader(paths: paths)
    }

    public func build(now: Date = Date()) -> Snapshot {
        let found = [claude.read()].compactMap { $0 } + codex.read(now: now)

        return Snapshot(
            generatedAt: now,
            providers: found.compactMap { withLiveWindowsOnly($0, now: now) }
        )
    }

    /// Drops windows whose reset time has passed.
    ///
    /// Their percentage describes an allowance that has already rolled over,
    /// and we have no reading of the replacement. A provider left with
    /// nothing live is omitted entirely rather than quoting a number from a
    /// window that no longer exists.
    private func withLiveWindowsOnly(
        _ snapshot: ProviderSnapshot,
        now: Date
    ) -> ProviderSnapshot? {
        let live = snapshot.liveWindows(asOf: now)
        guard !live.isEmpty else { return nil }
        guard live.count != snapshot.windows.count else { return snapshot }

        return ProviderSnapshot(
            provider: snapshot.provider,
            bucketName: snapshot.bucketName,
            planLabel: snapshot.planLabel,
            windows: live,
            sourceUpdatedAt: snapshot.sourceUpdatedAt
        )
    }
}
