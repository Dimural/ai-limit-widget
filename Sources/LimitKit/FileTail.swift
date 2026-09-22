import Foundation

/// Reads the last chunk of a file without loading the whole thing.
///
/// Codex rollout files reach tens of megabytes and are full of conversation
/// content. We only ever want the most recent `token_count` event, so we read
/// a bounded tail, and we open the file read-only so there is no possibility
/// of disturbing the CLI that owns it.
public enum FileTail {
    /// How much of a rollout file to read. A `token_count` event is well under
    /// 1 KB and one is emitted per turn, so 256 KB reaches back many turns
    /// while staying a single cheap read.
    public static let defaultByteLimit = 256 * 1024

    /// Returns the complete lines at the end of `url`.
    ///
    /// A partial first line is discarded: when we start mid-file the opening
    /// fragment is not valid JSON. A partial *last* line is also discarded,
    /// which is the common case when the CLI is mid-write.
    public static func lines(
        of url: URL,
        byteLimit: Int = defaultByteLimit
    ) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let readLength = min(UInt64(byteLimit), size)
        try handle.seek(toOffset: size - readLength)

        guard let data = try handle.readToEnd(), !data.isEmpty else { return [] }

        // Lossy conversion: a tail can slice a multi-byte character in half,
        // and one mangled character must not discard the whole read.
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")

        // Dropped because we may have started mid-line.
        if readLength < size, !lines.isEmpty { lines.removeFirst() }

        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
