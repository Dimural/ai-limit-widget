import Foundation

/// Reads and writes the snapshot file the widget renders from.
///
/// Writes are atomic — a temporary file in the same directory, then a rename —
/// so the widget can never observe a half-written file, no matter when the
/// system chooses to wake it. Files are created mode 0600: the snapshot holds
/// only percentages and timestamps, but there is no reason for anything other
/// than this user to read it.
public struct SnapshotStore {
    public init() {}

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func write(_ snapshot: Snapshot, to url: URL) throws {
        try Self.writeAtomically(data: Self.encoder.encode(snapshot), to: url)
    }

    /// Writes only when the numbers differ from what is already on disk, and
    /// reports whether it did.
    ///
    /// The collector watches the directory it writes into, so an
    /// unconditional write retriggers the watcher, which writes again, for as
    /// long as the app is running. Comparing before writing breaks that loop
    /// at its source: a write still happens whenever there is genuinely
    /// something new, and the refresh it provokes simply finds nothing to do.
    ///
    /// `generatedAt` is ignored in the comparison — it changes on every
    /// rebuild by definition, so including it would defeat the whole point.
    @discardableResult
    public func writeIfChanged(_ snapshot: Snapshot, to url: URL) throws -> Bool {
        if let existing = read(from: url), existing.providers == snapshot.providers {
            return false
        }
        try write(snapshot, to: url)
        return true
    }

    /// Returns `nil` for a missing, unreadable, corrupt, or future-versioned
    /// file. Every one of those is a "no data yet" state in the UI, which is
    /// always better than rendering a number we are not sure of.
    public func read(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? Self.decoder.decode(Snapshot.self, from: data),
              snapshot.schemaVersion <= Snapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }

    /// Shared by the store and the status line shim, which writes its capture
    /// file the same way and for the same reasons.
    public static func writeAtomically(data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let temporary = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: temporary.path
        )

        // rename(2) rather than FileManager.replaceItemAt, which throws when
        // the destination does not yet exist — the very first write. rename is
        // atomic whether or not the destination is there, so a reader sees
        // either the old contents or the new ones and never a partial file.
        guard rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }
}
