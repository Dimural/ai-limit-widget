import Foundation
import ServiceManagement

/// Registers AI Limits to start at login, so the widget keeps updating without
/// anyone remembering to launch anything.
///
/// `SMAppService` rather than a hand-written LaunchAgent plist: the
/// registration shows up in System Settings › General › Login Items, where the
/// user can see it and switch it off without going near a terminal. Nothing is
/// written into `~/Library/LaunchAgents`.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state. Registration can fail — most often because
    /// the app is being run from the build directory rather than
    /// `/Applications` — and the menu simply reflects that rather than
    /// claiming success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return isEnabled
        }
        return isEnabled
    }
}
