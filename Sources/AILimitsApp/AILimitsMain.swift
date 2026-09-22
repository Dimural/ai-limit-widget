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

/// Entry point.
///
/// `@MainActor` rather than top-level code in a `main.swift`: everything here
/// touches AppKit, and an explicit entry point keeps that isolation honest
/// instead of relying on top-level code's implicit main-actor rules.
@main
enum AILimitsMain {
    @MainActor
    static func main() {
        // Headless modes, used by scripts/uninstall.sh so removal works even
        // when the menu bar app cannot be clicked. They do their one job and
        // exit without starting any UI.
        switch CommandLine.arguments.dropFirst().first {
        case "--uninstall-hook":
            try? ClaudeHookInstaller().uninstall()
            return
        case "--print-snapshot":
            // For debugging and for agents: the exact data the widget renders.
            if let data = try? Data(contentsOf: Paths().snapshot) {
                FileHandle.standardOutput.write(data)
                print()
            } else {
                print("No snapshot yet.")
            }
            return
        default:
            break
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // Accessory, not regular: no Dock icon, and no menu bar takeover when
        // the app is focused.
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
