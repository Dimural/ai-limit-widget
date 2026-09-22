import CoreServices
import Foundation

/// Watches a directory tree and calls back when anything inside it changes.
///
/// This is what keeps AI Limits close to free when nothing is happening: the
/// collector does no work at all until a CLI actually writes something. There
/// is no polling loop over provider files.
///
/// FSEvents rather than `DispatchSource`, because Codex writes several levels
/// deep (`sessions/YYYY/MM/DD/rollout-*.jsonl`) and a `DispatchSource` on the
/// root would never see it.
final class DirectoryWatcher {
    /// Coalescing delay. Codex writes a burst of lines per turn, and one
    /// wake-up per turn is plenty — a shorter latency would cost battery to
    /// re-read numbers that have not changed.
    private static let latency: CFTimeInterval = 1.0

    private let url: URL
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit { stop() }

    /// Returns false when the directory does not exist — a provider that has
    /// never run. The collector's heartbeat picks it up if that changes.
    @discardableResult
    func start() -> Bool {
        guard stream == nil,
              FileManager.default.fileExists(atPath: url.path)
        else { return false }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            // NoDefer: report the first event immediately, then coalesce the
            // rest of the burst, so the first turn of a session shows up fast.
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
        ) else { return false }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
