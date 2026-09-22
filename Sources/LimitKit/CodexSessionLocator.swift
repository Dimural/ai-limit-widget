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
        let dayDirectories = datedDirectories(under: sessionsDirectory)
        for directory in dayDirectories.prefix(maxDatedDirectoriesToTry) {
            if let newest = newestRolloutFile(directlyIn: directory) { return newest }
        }
        // Layout changed, or sessions sit directly in the root.
        return newestRolloutFile(directlyIn: sessionsDirectory)
    }

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

    private static func newestRolloutFile(directlyIn directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.lastPathComponent.hasSuffix(".jsonl") }
            .max { lhs, rhs in modificationDate(of: lhs) < modificationDate(of: rhs) }
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
