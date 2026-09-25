import AppKit
import XCTest
@testable import LauncherCore

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testSettingsWindowLoadsAndSavesFields() throws {
        _ = NSApplication.shared
        let suite = "launcher-window-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let secrets = ServerURLSecretStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); secrets.delete() }
        let store = SettingsStore(defaults: defaults, secrets: secrets)
        try store.save(.init(dshPath: "/tmp/first-dsh", workspacePath: "/tmp/first-workspace"))
        let controller = SettingsWindowController(store: store)
        XCTAssertEqual(controller.window?.title, "Settings")
        XCTAssertEqual(controller.dshField.stringValue, "/tmp/first-dsh")
        controller.dshField.stringValue = "/tmp/second-dsh"
        controller.workspaceField.stringValue = "/tmp/second-workspace"
        controller.serverURLField.stringValue = "http://127.0.0.1:3080/?token=example"

        controller.save(nil)
        XCTAssertEqual(store.load().dshPath, "/tmp/second-dsh")
        XCTAssertEqual(store.load().workspacePath, "/tmp/second-workspace")
        XCTAssertEqual(store.load().existingServerURL, "http://127.0.0.1:3080/?token=example")
    }

    func testInvalidServerURLStaysVisibleAsError() throws {
        _ = NSApplication.shared
        let suite = "launcher-window-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let secrets = ServerURLSecretStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); secrets.delete() }
        let controller = SettingsWindowController(store: SettingsStore(defaults: defaults, secrets: secrets))
        controller.serverURLField.stringValue = "https://example.com:443/"
        controller.save(nil)
        XCTAssertFalse(controller.errorLabel.stringValue.isEmpty)
    }
}
