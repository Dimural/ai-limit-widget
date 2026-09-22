import XCTest

@testable import LimitKit

/// The shim runs inside every Claude Code render, so these tests care as much
/// about what it refuses to do as about what it extracts.
final class StatusLineCaptureTests: XCTestCase {
    /// A realistic status line payload: the limits we want, surrounded by
    /// session details we must not keep.
    private let payload = Data("""
    {
      "session_id": "c01f2dac-81a3-4195-92bc-714b78ed554c",
      "transcript_path": "/Users/someone/.claude/projects/-Users-someone-secret/abc.jsonl",
      "cwd": "/Users/someone/secret-project",
      "model": {"id": "claude-opus-5", "display_name": "Opus"},
      "rate_limits": {
        "five_hour": {"used_percentage": 42.5, "resets_at": "2026-09-22T05:00:00Z"},
        "seven_day": {"used_percentage": 18, "resets_at": "2026-09-28T05:00:00Z"}
      }
    }
    """.utf8)

    func testExtractsTheLimits() throws {
        let envelope = try XCTUnwrap(
            StatusLineCapture.envelope(fromStatusLinePayload: payload)
        )
        let snapshot = try XCTUnwrap(ClaudeReader.parse(captureFile: envelope))

        XCTAssertEqual(Set(snapshot.windows.map(\.label)), ["5-hour", "Weekly"])
    }

    /// The payload names the user's project directory, their transcript file
    /// and their session id. None of it may reach disk.
    func testKeepsNothingButTheLimitsAndATimestamp() throws {
        let envelope = try XCTUnwrap(
            StatusLineCapture.envelope(fromStatusLinePayload: payload)
        )
        let text = String(decoding: envelope, as: UTF8.self)

        XCTAssertFalse(text.contains("secret-project"))
        XCTAssertFalse(text.contains("transcript"))
        XCTAssertFalse(text.contains("c01f2dac"))
        XCTAssertFalse(text.contains("claude-opus-5"))

        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: envelope) as? [String: Any]
        )
        XCTAssertEqual(Set(root.keys), ["capturedAt", "rateLimits"])
    }

    /// API key, Bedrock and Vertex deployments have no plan limits at all.
    /// Writing nothing leaves the provider reading as not connected, which is
    /// the truth, rather than as 0% used.
    func testWritesNothingWhenThePayloadHasNoLimits() {
        XCTAssertNil(StatusLineCapture.envelope(
            fromStatusLinePayload: Data(#"{"session_id":"x","model":{"id":"y"}}"#.utf8)
        ))
        XCTAssertNil(StatusLineCapture.envelope(
            fromStatusLinePayload: Data(#"{"rate_limits":{}}"#.utf8)
        ))
    }

    func testSurvivesNonsenseOnStdin() {
        XCTAssertNil(StatusLineCapture.envelope(fromStatusLinePayload: Data()))
        XCTAssertNil(StatusLineCapture.envelope(fromStatusLinePayload: Data("not json".utf8)))
        XCTAssertNil(StatusLineCapture.envelope(fromStatusLinePayload: Data("[1,2,3]".utf8)))
    }

    // MARK: - Wrapping

    func testRecoversTheUsersOwnStatusLineCommand() {
        let state = Data("""
        {"installedAt":"2026-09-22T02:00:00Z","shimPath":"/x",
         "previousStatusLineJSON":"{\\"type\\":\\"command\\",\\"command\\":\\"python3 ~/.claude/statusline.py\\"}"}
        """.utf8)

        XCTAssertEqual(
            StatusLineCapture.wrappedCommand(fromHookState: state),
            "python3 ~/.claude/statusline.py"
        )
    }

    func testNoWrappedCommandWhenTheUserHadNoStatusLine() {
        XCTAssertNil(StatusLineCapture.wrappedCommand(fromHookState: nil))
        XCTAssertNil(StatusLineCapture.wrappedCommand(fromHookState: Data("{}".utf8)))
        XCTAssertNil(StatusLineCapture.wrappedCommand(fromHookState: Data("broken".utf8)))
        XCTAssertNil(StatusLineCapture.wrappedCommand(
            fromHookState: Data(#"{"previousStatusLineJSON":"{\"command\":\"   \"}"}"#.utf8)
        ))
    }

    // MARK: - Fallback line

    func testSummarisesLimitsWhenThereIsNothingToWrap() {
        XCTAssertEqual(
            StatusLineCapture.summaryLine(fromStatusLinePayload: payload),
            "5-hour 43% · Weekly 18%"
        )
    }

    func testSummaryIsEmptyRatherThanWrongWhenThereAreNoLimits() {
        XCTAssertEqual(StatusLineCapture.summaryLine(fromStatusLinePayload: Data("{}".utf8)), "")
        XCTAssertEqual(StatusLineCapture.summaryLine(fromStatusLinePayload: Data()), "")
    }
}
