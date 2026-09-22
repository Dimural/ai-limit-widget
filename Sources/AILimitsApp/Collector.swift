import Foundation
import LimitKit
import WidgetKit

/// Keeps the snapshot current and pushes it to the widget.
///
/// Cost is the whole design here. The collector does nothing until a provider
/// file changes, and even then it reads a bounded tail of one file. The only
/// timer is a slow heartbeat that exists so countdowns and staleness stay
/// right while everything is idle.
@MainActor
final class Collector {
    /// Recomputes while nothing is changing, so a card can go stale and a
    /// countdown can tick over even with both CLIs closed. Deliberately slow:
    /// at this interval the work is unmeasurable.
    private static let heartbeat: TimeInterval = 60

    /// WidgetKit budgets how often a widget may reload, and spending that
    /// budget on a busy session would leave none for later. Codex can write
    /// several times a minute; the widget only needs the latest.
    private static let minimumWidgetReloadInterval: TimeInterval = 60

    private let paths: Paths
    private let builder: SnapshotBuilder
    private let store = SnapshotStore()
    private let widgetBridge: WidgetBridge

    private var watchers: [DirectoryWatcher] = []
    private var heartbeatTimer: Timer?
    private var lastWidgetReload: Date = .distantPast
    private var pendingWidgetReload = false

    /// Latest snapshot, for the menu bar to render.
    private(set) var snapshot: Snapshot

    /// Called on the main queue whenever `snapshot` changes.
    var onUpdate: ((Snapshot) -> Void)?

    init(paths: Paths = Paths()) {
        self.paths = paths
        self.builder = SnapshotBuilder(paths: paths)
        self.widgetBridge = WidgetBridge(paths: paths)
        self.snapshot = Snapshot(generatedAt: .distantPast, providers: [])
    }

    func start() {
        // Codex writes rollout files here; the shim writes our capture file
        // there. Between them, every change that matters is covered.
        for directory in [paths.codexSessions, paths.appSupport] {
            let watcher = DirectoryWatcher(url: directory) { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
            watcher.start()
            watchers.append(watcher)
        }

        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: Self.heartbeat,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // The heartbeat only keeps the display honest; it must never wake a
        // sleeping Mac to do it.
        heartbeatTimer?.tolerance = Self.heartbeat / 2

        refresh()
    }

    func stop() {
        watchers.forEach { $0.stop() }
        watchers.removeAll()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// Rebuilds from the provider files and publishes the result.
    ///
    /// The menu bar is updated every time, because it is free. The widget is
    /// only touched when the numbers actually changed, to stay inside
    /// WidgetKit's reload budget.
    func refresh() {
        let rebuilt = builder.build()
        let numbersChanged = rebuilt.providers != snapshot.providers
        snapshot = rebuilt
        onUpdate?(rebuilt)

        try? store.write(rebuilt, to: paths.snapshot)

        guard numbersChanged else { return }
        widgetBridge.push(rebuilt)
        reloadWidgetWithinBudget()
    }

    /// Reloads at most once per interval, and makes sure the last change in a
    /// burst is not the one that gets dropped.
    private func reloadWidgetWithinBudget() {
        let elapsed = Date().timeIntervalSince(lastWidgetReload)
        guard elapsed >= Self.minimumWidgetReloadInterval else {
            guard !pendingWidgetReload else { return }
            pendingWidgetReload = true
            let delay = Self.minimumWidgetReloadInterval - elapsed
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.pendingWidgetReload = false
                self?.reloadWidgetWithinBudget()
            }
            return
        }

        lastWidgetReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
