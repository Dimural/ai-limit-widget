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
        Snapshot(
            generatedAt: now,
            providers: [claude.read(), codex.read()].compactMap { $0 }
        )
    }
}
