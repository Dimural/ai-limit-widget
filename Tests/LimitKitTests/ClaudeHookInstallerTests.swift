import XCTest

@testable import LimitKit

/// The installer is the only code in AI Limits that writes outside its own
/// directories, so its guarantees are tested harder than anything else here.
final class ClaudeHookInstallerTests: XCTestCase {
    private let shim = URL(fileURLWithPath: "/Applications/AILimits.app/Contents/Resources/ai-limits-statusline")

    private func settings(in home: TemporaryHome) throws -> [String: Any] {
        let data = try Data(contentsOf: home.paths.claudeSettings)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInstallPointsTheStatusLineAtTheShim() throws {
        let home = try TemporaryHome()
        try home.write(#"{"model":"opus"}"#, to: ".claude/settings.json")

        try ClaudeHookInstaller(paths: home.paths).install(shimPath: shim)

        let statusLine = try XCTUnwrap(try settings(in: home)["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, shim.path)
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["refreshInterval"] as? Int, ClaudeHookInstaller.refreshIntervalSeconds)
    }

    func testInstallPreservesEverySettingItDoesNotOwn() throws {
        let home = try TemporaryHome()
        try home.write(
            #"{"model":"opus","theme":"dark","permissions":{"allow":["Bash(ls:*)"]}}"#,
            to: ".claude/settings.json"
        )

        try ClaudeHookInstaller(paths: home.paths).install(shimPath: shim)

        let result = try settings(in: home)
        XCTAssertEqual(result["model"] as? String, "opus")
        XCTAssertEqual(result["theme"] as? String, "dark")
        let permissions = try XCTUnwrap(result["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["allow"] as? [String], ["Bash(ls:*)"])
    }

    func testInstallBacksUpTheOriginalFile() throws {
        let home = try TemporaryHome()
        let original = #"{"model":"opus"}"#
        try home.write(original, to: ".claude/settings.json")

        try ClaudeHookInstaller(paths: home.paths).install(shimPath: shim)

        XCTAssertEqual(try home.read(".claude/settings.json.ailimits-backup"), original)
    }

    /// Restoring must return the user's own status line, so the backup has to
    /// survive a second install rather than being replaced by our own edit.
    func testSecondInstallDoesNotOverwriteTheBackup() throws {
        let home = try TemporaryHome()
        let original = #"{"statusLine":{"type":"command","command":"python3 ~/.claude/statusline.py"}}"#
        try home.write(original, to: ".claude/settings.json")
        let installer = ClaudeHookInstaller(paths: home.paths)

        try installer.install(shimPath: shim)
        try installer.install(shimPath: shim)

        XCTAssertEqual(try home.read(".claude/settings.json.ailimits-backup"), original)
    }

    func testUninstallRestoresThePreviousStatusLineExactly() throws {
        let home = try TemporaryHome()
        try home.write(
            #"{"statusLine":{"type":"command","command":"python3 ~/.claude/statusline.py","padding":0}}"#,
            to: ".claude/settings.json"
        )
        let installer = ClaudeHookInstaller(paths: home.paths)

        try installer.install(shimPath: shim)
        try installer.uninstall()

        let statusLine = try XCTUnwrap(try settings(in: home)["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, "python3 ~/.claude/statusline.py")
        XCTAssertEqual(statusLine["padding"] as? Int, 0)
        XCTAssertFalse(ClaudeHookInstaller(paths: home.paths).isInstalled())
    }

    /// Two installs then one uninstall must still leave no trace of us.
    func testUninstallAfterRepeatedInstallsStillRestores() throws {
        let home = try TemporaryHome()
        try home.write(
            #"{"statusLine":{"type":"command","command":"mine.sh"}}"#,
            to: ".claude/settings.json"
        )
        let installer = ClaudeHookInstaller(paths: home.paths)

        try installer.install(shimPath: shim)
        try installer.install(shimPath: shim)
        try installer.uninstall()

        let statusLine = try XCTUnwrap(try settings(in: home)["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, "mine.sh")
    }

    func testUninstallRemovesTheKeyWhenThereWasNoStatusLineBefore() throws {
        let home = try TemporaryHome()
        try home.write(#"{"model":"opus"}"#, to: ".claude/settings.json")
        let installer = ClaudeHookInstaller(paths: home.paths)

        try installer.install(shimPath: shim)
        try installer.uninstall()

        let result = try settings(in: home)
        XCTAssertNil(result["statusLine"])
        XCTAssertEqual(result["model"] as? String, "opus")
    }

    func testUninstallPreservesSettingsChangedAfterInstalling() throws {
        let home = try TemporaryHome()
        try home.write(#"{"model":"opus"}"#, to: ".claude/settings.json")
        let installer = ClaudeHookInstaller(paths: home.paths)
        try installer.install(shimPath: shim)

        var changed = try settings(in: home)
        changed["theme"] = "light"
        try Data(try JSONSerialization.data(withJSONObject: changed))
            .write(to: home.paths.claudeSettings)

        try installer.uninstall()

        XCTAssertEqual(try settings(in: home)["theme"] as? String, "light")
    }

    /// Rewriting a file we cannot parse would destroy settings we cannot read,
    /// so the installer refuses and leaves it byte-for-byte alone.
    func testCorruptSettingsAreRefusedAndLeftUntouched() throws {
        let home = try TemporaryHome()
        let corrupt = "{ this is not json"
        try home.write(corrupt, to: ".claude/settings.json")

        XCTAssertThrowsError(try ClaudeHookInstaller(paths: home.paths).install(shimPath: shim))
        XCTAssertEqual(try home.read(".claude/settings.json"), corrupt)
        XCTAssertFalse(home.exists(".claude/settings.json.ailimits-backup"))
    }

    func testInstallsCleanlyWhenNoSettingsFileExists() throws {
        let home = try TemporaryHome()

        try ClaudeHookInstaller(paths: home.paths).install(shimPath: shim)

        XCTAssertTrue(ClaudeHookInstaller(paths: home.paths).isInstalled())
    }

    func testUninstallIsSafeWhenNothingWasEverInstalled() throws {
        let home = try TemporaryHome()
        XCTAssertNoThrow(try ClaudeHookInstaller(paths: home.paths).uninstall())
    }

    func testIsInstalledReportsForeignStatusLinesAsNotOurs() throws {
        let home = try TemporaryHome()
        try home.write(
            #"{"statusLine":{"type":"command","command":"python3 ~/.claude/statusline.py"}}"#,
            to: ".claude/settings.json"
        )

        XCTAssertFalse(ClaudeHookInstaller(paths: home.paths).isInstalled())
    }
}
