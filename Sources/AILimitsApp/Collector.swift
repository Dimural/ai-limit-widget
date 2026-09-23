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

    private let paths: Paths
    private let builder: SnapshotBuilder
    private let store = SnapshotStore()
    private let widgetBridge: WidgetBridge

    private var watchers: [DirectoryWatcher] = []
    private var heartbeatTimer: Timer?
    /// See `ReloadBudget`: WidgetKit limits how often a widget may reload.
    private var reloadBudget = ReloadBudget()

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
        // First, so our own directory exists before a watcher is pointed at it.
        refresh()

        // Codex writes rollout files here; the shim writes our capture file
        // there. Between them, every change that matters is covered.
        for directory in [paths.codexSessions, paths.appSupport] {
            watchers.append(DirectoryWatcher(url: directory) { [weak self] in
                // Bound before the Task: capturing the weak variable itself
                // inside a concurrent closure is a data race, and older Swift
                // toolchains reject it outright.
                guard let self else { return }
                Task { @MainActor in self.refresh() }
            })
        }
        attachWatchers()

        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: Self.heartbeat,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
        // The heartbeat only keeps the display honest; it must never wake a
        // sleeping Mac to do it.
        heartbeatTimer?.tolerance = Self.heartbeat / 2
    }

    /// A directory that does not exist yet cannot be watched — a provider that
    /// has never run, or our own directory before the first write. This is
    /// retried on every heartbeat, so installing Codex later starts being
    /// picked up without restarting the app. `start()` is idempotent.
    private func attachWatchers() {
        for watcher in watchers { watcher.start() }
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
        attachWatchers()

        let rebuilt = builder.build()
        snapshot = rebuilt
        onUpdate?(rebuilt)

        // Only writes when something actually changed. This directory is
        // watched, so writing unconditionally would wake the collector again
        // and again for as long as the app ran.
        guard (try? store.writeIfChanged(rebuilt, to: paths.snapshot)) == true else { return }

        widgetBridge.push(rebuilt)
        reloadWidgetWithinBudget()
    }

    /// Applies `ReloadBudget`'s decision. The waiting is all that lives here;
    /// the rule itself is in LimitKit, where it is tested.
    private func reloadWidgetWithinBudget() {
        switch reloadBudget.requestReload() {
        case .reloadNow:
            WidgetCenter.shared.reloadAllTimelines()
        case .alreadyPending:
            break
        case .retryAfter(let delay):
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                self.reloadBudget.retryCameDue()
                self.reloadWidgetWithinBudget()
            }
        }
    }
}
