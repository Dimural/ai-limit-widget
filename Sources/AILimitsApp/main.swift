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

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Accessory, not regular: no Dock icon, no menu bar takeover when focused.
application.setActivationPolicy(.accessory)
application.run()
