import Foundation
import LimitKit

/// Hands the snapshot to the widget extension.
///
/// macOS requires widget extensions to be sandboxed, so the widget cannot read
/// `~/.claude` or `~/.codex` itself, and the usual App Group workaround needs
/// an entitlement that a locally built app does not have.
///
/// Instead the collector — which is not sandboxed — writes the snapshot
/// directly into the widget extension's own container. The sandbox restricts
/// what the extension may reach, not what other processes may place inside it,
/// and an extension reading a file in its own container needs no entitlement
/// at all. The push is one-way: nothing is ever read back.
struct WidgetBridge {
    private let paths: Paths
    private let store = SnapshotStore()

    init(paths: Paths) {
        self.paths = paths
    }

    /// Fails quietly. The container does not exist until the widget has been
    /// added to the desktop at least once, and a user who has not added it is
    /// not waiting for anything.
    func push(_ snapshot: Snapshot) {
        try? store.write(snapshot, to: paths.widgetContainerSnapshot)
    }
}
