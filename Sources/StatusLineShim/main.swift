import Foundation
import LimitKit

// AI Limits status line shim.
//
// Claude Code runs this on every status line render and pipes it a JSON
// document containing `rate_limits`. This binary captures those numbers for
// the widget, then runs whatever status line command the user had configured
// before installing, so their own status line is unchanged.
//
// Two rules govern everything here:
//
//  1. Never break the status line. Whatever goes wrong, the user's command
//     still runs and its output still reaches Claude Code, and this process
//     always exits 0.
//  2. Never be slow. This runs on every render, so it does one small write
//     and then hands over.
//
// The interesting logic lives in LimitKit's StatusLineCapture, where it can be
// tested. What remains here is process wiring.

/// A wrapped command that hangs would hang the status line, so it gets a
/// bounded amount of time and is then abandoned.
let wrappedCommandTimeout: TimeInterval = 5

let paths = Paths()
let payload = FileHandle.standardInput.readDataToEndOfFile()

if let envelope = StatusLineCapture.envelope(fromStatusLinePayload: payload) {
    try? SnapshotStore.writeAtomically(data: envelope, to: paths.claudeSnapshot)
}

let hookState = try? Data(contentsOf: paths.hookState)

if let command = StatusLineCapture.wrappedCommand(fromHookState: hookState) {
    runWrapped(command, feeding: payload)
} else {
    print(StatusLineCapture.summaryLine(fromStatusLinePayload: payload))
}
exit(0)

/// Runs the user's own status line command with the same stdin Claude Code
/// gave us, letting it write straight through to our stdout and stderr.
///
/// It runs under `/bin/sh` because the recorded value is a shell command line
/// that may contain `~`, pipes or arguments. This introduces no new trust: it
/// is the exact string Claude Code was already executing before we installed.
func runWrapped(_ command: String, feeding payload: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]

    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    guard (try? process.run()) != nil else { return }

    try? input.fileHandleForWriting.write(contentsOf: payload)
    try? input.fileHandleForWriting.close()

    let deadline = Date().addingTimeInterval(wrappedCommandTimeout)
    while process.isRunning, Date() < deadline {
        usleep(2_000)
    }
    if process.isRunning { process.terminate() }
}
