import AppKit
import LimitKit

/// The menu bar readout and the app's only user interface.
///
/// The glyph carries the one number worth glancing at — the window closest to
/// running out, across every allowance — and the menu carries the detail.
/// There is no settings window: the three things worth changing are toggles,
/// and they belong in the menu next to what they affect.
@MainActor
final class MenuBarController: NSObject {
    /// Wide enough for a long allowance name such as GPT-5.3-Codex-Spark
    /// without the bars shrinking to nothing.
    private static let menuWidth: CGFloat = 288

    private let statusItem: NSStatusItem
    private let paths: Paths
    private let installer: ClaudeHookInstaller
    private let onRefresh: () -> Void

    private var snapshot: Snapshot

    init(paths: Paths, onRefresh: @escaping () -> Void) {
        self.paths = paths
        self.installer = ClaudeHookInstaller(paths: paths)
        self.onRefresh = onRefresh
        self.snapshot = Snapshot(generatedAt: .distantPast, providers: [])
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        render()
    }

    func update(with snapshot: Snapshot) {
        self.snapshot = snapshot
        render()
    }

    // MARK: - The glyph

    private func render() {
        guard let button = statusItem.button else { return }

        // The tightest window across every allowance: whichever will stop
        // work first is the only one that earns a permanent place on screen.
        let tightest = snapshot.providers.compactMap(\.tightestWindow)
            .max { $0.usedPercent < $1.usedPercent }

        button.image = MenuBarIcon.image(
            usedPercent: tightest?.usedPercent,
            appearance: button.effectiveAppearance
        )
        button.imagePosition = .imageLeading

        guard let tightest else {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "AI Limits — nothing reporting yet"
            return
        }

        button.attributedTitle = NSAttributedString(
            string: " \(Int(tightest.usedPercent.rounded()))%",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        button.toolTip = snapshot.providers
            .map { "\($0.title): \(summary(of: $0))" }
            .joined(separator: "\n")
    }

    private func summary(of allowance: ProviderSnapshot) -> String {
        allowance.windows
            .map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }
            .joined(separator: ", ")
    }

    // MARK: - The menu

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        if snapshot.providers.isEmpty {
            menu.addItem(hosting(EmptyStateView(width: Self.menuWidth)))
        }

        for (index, allowance) in snapshot.providers.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(hosting(AllowanceHeaderView(allowance: allowance, width: Self.menuWidth)))
            for window in allowance.windows {
                menu.addItem(hosting(WindowRowView(window: window, width: Self.menuWidth)))
            }
        }

        menu.addItem(.separator())
        menu.addItem(action(
            installer.isInstalled() ? "Disconnect Claude Code" : "Connect Claude Code…",
            #selector(toggleClaudeHook)
        ))

        let login = action("Open at Login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(action("Refresh Now", #selector(refresh), key: "r"))
        menu.addItem(.separator())
        menu.addItem(action("Quit AI Limits", #selector(quit), key: "q"))
    }

    /// Wraps a drawn view as a menu row.
    ///
    /// These rows are readouts, not commands, so they take no action and
    /// never highlight — but they stay enabled, because macOS greys out
    /// disabled rows and a greyed reading looks like a broken one.
    private func hosting(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func toggleClaudeHook() {
        do {
            if installer.isInstalled() {
                try installer.uninstall()
            } else {
                try installer.install(shimPath: Self.shimPath())
            }
        } catch {
            present(error)
        }
        onRefresh()
    }

    /// The shim ships inside this app bundle. When running from the build
    /// directory there is no bundle, so the built binary beside us is used
    /// instead — that is how `make run` works during development.
    static func shimPath() -> URL {
        if let bundled = Bundle.main.url(
            forResource: ClaudeHookInstaller.shimExecutableName,
            withExtension: nil
        ) {
            return bundled
        }
        return URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appending(path: ClaudeHookInstaller.shimExecutableName)
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        rebuildMenu()
    }

    @objc private func refresh() {
        onRefresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "AI Limits could not change your Claude Code settings"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension MenuBarController: NSMenuDelegate {
    /// Built when opened rather than on every snapshot: nobody is looking at
    /// it the rest of the time, and the countdowns should be right at the
    /// moment they are read.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}
