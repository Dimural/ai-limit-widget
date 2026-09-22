import AppKit
import LimitKit

// AI Limits menu bar app.
//
// This process is the collector: it watches the provider files, keeps the
// snapshot current, and pushes it to the widget. It has no window and no Dock
// icon (see LSUIElement in Resources/AILimits-Info.plist) — the menu bar is
// the whole interface.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths = Paths()
    private var collector: Collector?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let collector = Collector(paths: paths)
        let menuBar = MenuBarController(paths: paths) { [weak collector] in
            collector?.refresh()
        }

        collector.onUpdate = { [weak menuBar] snapshot in
            menuBar?.update(with: snapshot)
        }
        collector.start()

        self.collector = collector
        self.menuBar = menuBar
    }

    func applicationWillTerminate(_ notification: Notification) {
        collector?.stop()
    }
}

// Headless modes, used by scripts/uninstall.sh so removal works even when the
// menu bar app cannot be clicked. They do their one job and exit without
// starting any UI.
switch CommandLine.arguments.dropFirst().first {
case "--uninstall-hook":
    try? ClaudeHookInstaller().uninstall()
    exit(0)
case "--print-snapshot":
    // For debugging and for agents: the exact data the widget renders.
    let paths = Paths()
    if let data = try? Data(contentsOf: paths.snapshot) {
        FileHandle.standardOutput.write(data)
        print()
    } else {
        print("No snapshot yet.")
    }
    exit(0)
default:
    break
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Accessory, not regular: no Dock icon, no menu bar takeover when focused.
application.setActivationPolicy(.accessory)
application.run()
