import LimitKit
import WidgetKit

/// Supplies the widget with snapshots to render.
///
/// The extension is sandboxed and cannot read `~/.claude` or `~/.codex`. It
/// reads one file that the menu bar app pushes into this extension's own
/// container, which the sandbox permits without any entitlement.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct SnapshotTimelineProvider: TimelineProvider {
    /// How far ahead to describe, and how finely.
    ///
    /// WidgetKit decides when to actually reload, so the timeline has to stand
    /// on its own for a while. Entries every five minutes keep the "as of …"
    /// staleness label honest even if no reload arrives; the reset countdowns
    /// tick live within a single entry and cost nothing.
    private static let horizon: TimeInterval = 60 * 60
    private static let step: TimeInterval = 5 * 60

    private let store = SnapshotStore()
    private let paths = Paths()

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: Snapshot.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // The widget gallery previews with `isPreview`, before any data has
        // been pushed; sample numbers show what the widget is for.
        let snapshot: Snapshot? = context.isPreview ? Snapshot.preview : currentSnapshot()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = currentSnapshot()
        let now = Date()

        let entries = stride(from: 0, through: Self.horizon, by: Self.step).map { offset in
            SnapshotEntry(date: now.addingTimeInterval(offset), snapshot: snapshot)
        }

        // The menu bar app reloads the timeline as soon as the numbers change,
        // so this end-of-horizon refresh is only the fallback for when the app
        // is not running.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.horizon))))
    }

    private func currentSnapshot() -> Snapshot? {
        store.read(from: paths.snapshotForWidget)
    }
}

extension Snapshot {
    /// Shown in the widget gallery, where there is no real data yet.
    static let preview = Snapshot(
        generatedAt: Date(),
        providers: [
            ProviderSnapshot(
                provider: .claude,
                planLabel: "max",
                windows: [
                    LimitWindow(label: "5-hour", usedPercent: 68, resetsAt: Date().addingTimeInterval(7_400)),
                    LimitWindow(label: "Weekly", usedPercent: 24, resetsAt: Date().addingTimeInterval(320_000)),
                ],
                sourceUpdatedAt: Date()
            ),
            ProviderSnapshot(
                provider: .codex,
                planLabel: "plus",
                windows: [
                    LimitWindow(label: "5-hour", usedPercent: 33, resetsAt: Date().addingTimeInterval(4_200)),
                    LimitWindow(label: "Weekly", usedPercent: 7, resetsAt: Date().addingTimeInterval(500_000)),
                ],
                sourceUpdatedAt: Date()
            ),
        ]
    )
}
