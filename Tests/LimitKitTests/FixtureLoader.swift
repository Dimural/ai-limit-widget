import Foundation
import XCTest

@testable import LimitKit

/// Fixtures are real payloads captured from Claude Code and Codex on a working
/// machine, with conversation content and identifiers stripped. Tests read
/// them rather than hand-built mocks, so a test passing means the parser
/// handles the shape these tools genuinely emit.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func lines(_ name: String) throws -> [String] {
        try String(contentsOf: url(name), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func url(_ name: String) -> URL {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: nil, subdirectory: "Fixtures"
        ) else {
            fatalError("Missing fixture \(name). Fixtures live in Tests/LimitKitTests/Fixtures.")
        }
        return url
    }
}

/// A throwaway home directory, so no test can read or write the real
/// `~/.claude` or `~/.codex`.
final class TemporaryHome {
    let url: URL
    var paths: Paths { Paths(home: url) }

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ailimits-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ contents: String, to relativePath: String) throws {
        let destination = url.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: destination, atomically: true, encoding: .utf8)
    }

    func read(_ relativePath: String) throws -> String {
        try String(contentsOf: url.appending(path: relativePath), encoding: .utf8)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appending(path: relativePath).path)
    }
}
