import Foundation

/// Finds the Codex rollout file that was written most recently.
///
/// Codex lays sessions out as `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
/// We walk that structure newest-first so the cost stays flat no matter how
/// many years of sessions have accumulated, rather than enumerating the whole
/// tree. Codex also keeps a SQLite index of these files; we deliberately do
/// not open it, so there is no chance of contending with Codex's own locks.
public enum CodexSessionLocator {
    /// How many dated directories to fall back through. A user who has not run
    /// Codex for a few days should still see their last known numbers, but we
    /// stop well short of walking years of history.
    private static let maxDatedDirectoriesToTry = 30

    public static func newestRollout(in sessionsDirectory: URL) -> URL? {
        recentRollouts(in: sessionsDirectory, modifiedSince: .distantPast, limit: 1).first
    }

    /// Rollout files touched since `modifiedSince`, newest first.
    ///
    /// Codex reports a separate allowance per model, and they live in
    /// different session files — so finding them all means looking at more
    /// than the newest file. `modifiedSince` keeps that bounded: an allowance
    /// from before the longest window has already rolled over and has nothing
    /// current to tell us, so there is no reason to read it.
    public static func recentRollouts(
        in sessionsDirectory: URL,
        modifiedSince: Date,
        limit: Int = maxFilesToRead
    ) -> [URL] {
        var found: [(url: URL, modified: Date)] = []

        for directory in datedDirectories(under: sessionsDirectory).prefix(maxDatedDirectoriesToTry) {
            let candidates = rolloutFiles(directlyIn: directory)
                .filter { $0.modified >= modifiedSince }
            found.append(contentsOf: candidates)
            if found.count >= limit { break }
        }

        // Layout changed, or sessions sit directly in the root.
        if found.isEmpty {
            found = rolloutFiles(directlyIn: sessionsDirectory)
                .filter { $0.modified >= modifiedSince }
        }

        return found
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map(\.url)
    }

    /// A ceiling on work, not a meaningful limit: a week of sessions is
    /// nowhere near this many, and reading is skipped entirely for files
    /// older than the longest window.
    public static let maxFilesToRead = 40

    /// Year/month/day directories, newest first. Names are compared as strings
    /// because Codex zero-pads them, which makes lexicographic order correct.
    private static func datedDirectories(under root: URL) -> [URL] {
        numericSubdirectories(of: root).flatMap { year in
            numericSubdirectories(of: year).flatMap { month in
                numericSubdirectories(of: month)
            }
        }
    }

    private static func numericSubdirectories(of directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
                return isDirectory == true && url.lastPathComponent.allSatisfy(\.isNumber)
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static func rolloutFiles(directlyIn directory: URL) -> [(url: URL, modified: Date)] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.lastPathComponent.hasSuffix(".jsonl") }
            .map { ($0, modificationDate(of: $0)) }
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
