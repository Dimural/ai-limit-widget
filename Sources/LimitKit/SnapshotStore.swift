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
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        // Replaces any existing file in one step; readers see either the old
        // contents or the new ones, never a partial write.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
