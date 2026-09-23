import AppKit
import LimitKit

/// The menu bar readout and the app's only user interface.
///
/// The title carries the one number worth glancing at — the tightest window
/// across every connected provider — and the menu carries the detail. There is
/// no settings window: the three things worth changing are all toggles, and
/// they live in the menu.
@MainActor
final class MenuBarController: NSObject {
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

    // MARK: - Title

    private func render() {
        guard let button = statusItem.button else { return }

        let tightest = snapshot.providers.compactMap(\.tightestWindow)
            .max { $0.usedPercent < $1.usedPercent }

        guard let tightest else {
            button.attributedTitle = styled("AI ·", severity: nil)
            button.toolTip = "AI Limits — no provider connected yet"
            return
        }

        let percent = Int(tightest.usedPercent.rounded())
        button.attributedTitle = styled(
            "AI \(percent)%",
            severity: Presentation.severity(forUsedPercent: tightest.usedPercent)
        )
        button.toolTip = snapshot.providers
            .map { "\($0.provider.displayName): \(summary(of: $0))" }
            .joined(separator: "\n")
    }

    /// Colour is reinforcement, never the only signal — the percentage is
    /// always spelled out, so this still reads correctly in monochrome.
    private func styled(_ text: String, severity: Presentation.Severity?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]
        switch severity {
        case .critical: attributes[.foregroundColor] = NSColor.systemOrange
        case .exhausted: attributes[.foregroundColor] = NSColor.systemRed
        default: break
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func summary(of provider: ProviderSnapshot) -> String {
        provider.windows
            .map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }
            .joined(separator: ", ")
    }

    // MARK: - Menu

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        if snapshot.providers.isEmpty {
            menu.addItem(disabled("No provider connected"))
            menu.addItem(disabled("Run Codex, or connect Claude Code below."))
        }

        for provider in snapshot.providers {
            menu.addItem(header(for: provider))
            for window in provider.windows {
                menu.addItem(disabled(row(for: window)))
            }
            menu.addItem(.separator())
        }

        let connect = NSMenuItem(
            title: installer.isInstalled()
                ? "Disconnect Claude Code"
                : "Connect Claude Code…",
            action: #selector(toggleClaudeHook),
            keyEquivalent: ""
        )
        connect.target = self
        menu.addItem(connect)

        let login = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AI Limits", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func header(for provider: ProviderSnapshot) -> NSMenuItem {
        var title = provider.provider.displayName
        if let plan = provider.planLabel { title += " · \(plan)" }
        if provider.isStale(threshold: Presentation.stalenessThreshold) {
            title += " · as of \(Self.timeFormatter.string(from: provider.sourceUpdatedAt))"
        }

        let item = disabled(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
        )
        return item
    }

    /// `5-hour   ███████░░░  42%  ·  resets in 2h 14m`
    private func row(for window: LimitWindow) -> String {
        var text = "\(window.label.padding(toLength: 9, withPad: " ", startingAt: 0))"
        text += bar(for: window.usedPercent)
        text += String(format: " %3d%%", Int(window.usedPercent.rounded()))
        if let resetsAt = window.resetsAt {
            text += "  ·  resets in \(Presentation.compactCountdown(until: resetsAt))"
        }
        return text
    }

    private func bar(for percent: Double, width: Int = 10) -> String {
        let filled = Int((percent / 100 * Double(width)).rounded())
        return String(repeating: "█", count: min(filled, width))
            + String(repeating: "░", count: max(width - filled, 0))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
        )
        return item
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

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
    /// Built on open rather than on every snapshot: nobody is looking at it the
    /// rest of the time, and countdowns should be correct at the moment they
    /// are read.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}
