import Foundation

/// The logic behind the Claude Code status line shim, kept here so it can be
/// tested. `Sources/StatusLineShim` is only process wiring on top of this.
///
/// Claude Code pipes a JSON document to the configured status line command on
/// every render. That document contains `rate_limits` — the account's real,
/// server-side usage windows — alongside a good deal that is none of our
/// business: the working directory, the transcript path, the session id, the
/// model. Only `rate_limits` is ever extracted or stored.
public enum StatusLineCapture {
    /// Builds the file the reader later parses: the `rate_limits` object and
    /// the time it was captured, and nothing else.
    ///
    /// Returns `nil` when the payload carries no limits, which is normal on
    /// plans and deployments that have none (API key, Bedrock, Vertex). In
    /// that case no file is written and the provider reads as not connected.
    public static func envelope(fromStatusLinePayload data: Data) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any],
              !limits.isEmpty
        else { return nil }

        let envelope: [String: Any] = [
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "rateLimits": limits,
        ]
        return try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    /// The status line command configured before AI Limits was installed,
    /// recorded by `ClaudeHookInstaller` so the shim can keep running it.
    ///
    /// Returns `nil` when the user had no status line, in which case the shim
    /// prints `summaryLine` instead of leaving the line blank.
    public static func wrappedCommand(fromHookState data: Data?) -> String? {
        guard let data,
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let json = state["previousStatusLineJSON"] as? String,
              let statusLine = try? JSONSerialization.jsonObject(with: Data(json.utf8))
                  as? [String: Any],
              let command = statusLine["command"] as? String,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return command
    }

    /// A compact rendering of the same numbers the widget shows, used only
    /// when there is no status line to wrap: `5-hour 42% · Weekly 18%`.
    public static func summaryLine(fromStatusLinePayload data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"],
              let capture = try? JSONSerialization.data(withJSONObject: ["rateLimits": limits]),
              let snapshot = ClaudeReader.parse(captureFile: capture)
        else { return "" }

        return snapshot.windows
            .map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }
            .joined(separator: " · ")
    }
}
