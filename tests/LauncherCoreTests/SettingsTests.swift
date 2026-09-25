import Foundation
import XCTest
@testable import LauncherCore

final class SettingsTests: XCTestCase {
    func testSettingsPersistPathsAndTokenURL() throws {
        let suite = "launcher-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let secrets = ServerURLSecretStore(service: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            secrets.delete()
        }

        let store = SettingsStore(defaults: defaults, secrets: secrets)
        let settings = LauncherSettings(dshPath: "/tmp/dsh", workspacePath: "/tmp/workspace",
                                        existingServerURL: "http://127.0.0.1:3080/?token=secret")
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
        XCTAssertNil(defaults.string(forKey: "existingServerURL"))
    }

    func testInvalidRemoteServerURLIsRejected() throws {
        let suite = "launcher-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let secrets = ServerURLSecretStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); secrets.delete() }
        let store = SettingsStore(defaults: defaults, secrets: secrets)

        XCTAssertThrowsError(try store.save(.init(dshPath: nil, workspacePath: "/tmp",
                                                  existingServerURL: "https://example.com:443/")))
        XCTAssertThrowsError(try store.save(.init(dshPath: nil, workspacePath: "   ")))
        XCTAssertThrowsError(try store.save(.init(dshPath: nil, workspacePath: "relative/path")))
    }
}
