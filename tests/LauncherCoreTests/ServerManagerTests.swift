import Foundation
import XCTest
@testable import LauncherCore

final class ServerManagerTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../fixtures/dsh").standardizedFileURL
    }

    func testStartsTokenServerAndTerminatesOwnedProcess() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let manager = ServerManager(environment: ["FAKE_DSH_MODE": "token", "FAKE_DSH_MARKER": marker.path])
        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())

        let connection = try manager.connect(settings: settings, discoverExisting: false, timeout: 5)
        XCTAssertTrue(connection.isOwned)
        XCTAssertEqual(connection.url.query, "token=test-secret")
        XCTAssertEqual(HTTPProbe.status(connection.url), 200)
        manager.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testStartFailureReturnsPromptly() {
        let manager = ServerManager(environment: ["FAKE_DSH_MODE": "exit"])
        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())
        let start = Date()
        XCTAssertThrowsError(try manager.connect(settings: settings, discoverExisting: false, timeout: 5))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testStartsBareURLServer() throws {
        let manager = ServerManager(environment: ["FAKE_DSH_MODE": "bare"])
        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())
        defer { manager.stop() }
        let connection = try manager.connect(settings: settings, discoverExisting: false, timeout: 5)
        XCTAssertTrue(connection.isOwned)
        XCTAssertNil(connection.url.query)
    }

    func testStartsWhenDiscoveryFindsNoRunningServer() throws {
        var discoveryCalled = false
        let manager = ServerManager(environment: ["FAKE_DSH_MODE": "bare"], discover: { _ in
            discoveryCalled = true
            return nil
        })
        defer { manager.stop() }
        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())
        let connection = try manager.connect(settings: settings, timeout: 5)
        XCTAssertTrue(discoveryCalled)
        XCTAssertTrue(connection.isOwned)
        XCTAssertTrue(manager.isOwnedProcessRunning)
    }

    func testMissingDshFailsBeforeDiscoveryOrLaunch() {
        let manager = ServerManager(discover: { _ in
            XCTFail("Discovery should not run without an installed dsh")
            return nil
        })
        let settings = LauncherSettings(dshPath: "/definitely/missing/dsh", workspacePath: NSTemporaryDirectory())
        XCTAssertThrowsError(try manager.connect(settings: settings)) { error in
            guard case DshLocatorError.missing = error else { return XCTFail("Expected missing dsh") }
        }
    }

    func testAttachedServerIsNotStopped() throws {
        let external = Process()
        external.executableURL = fixture
        external.arguments = ["web", "--no-open", "--port", "0"]
        external.environment = ProcessInfo.processInfo.environment.merging(["FAKE_DSH_MODE": "bare"]) { _, new in new }
        let output = Pipe()
        external.standardOutput = output
        try external.run()
        defer { external.terminate(); external.waitUntilExit() }
        let line = try XCTUnwrap(String(data: output.fileHandleForReading.availableData, encoding: .utf8))
        let url = try XCTUnwrap(ServerURL.fromStartupLine(line))
        let manager = ServerManager(discover: { _ in ServerConnection(url: url, isOwned: false) })

        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())
        let connection = try manager.connect(settings: settings)
        XCTAssertFalse(connection.isOwned)
        manager.stop()
        XCTAssertTrue(external.isRunning)
    }

    func testTimeoutStopsServerWithoutStartupLine() {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let manager = ServerManager(environment: ["FAKE_DSH_MODE": "silent", "FAKE_DSH_MARKER": marker.path])
        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())
        XCTAssertThrowsError(try manager.connect(settings: settings, discoverExisting: false, timeout: 0.5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testStartupErrorRedactsToken() {
        let manager = ServerManager(environment: ["FAKE_DSH_MODE": "exit-secret"])
        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())
        XCTAssertThrowsError(try manager.connect(settings: settings, discoverExisting: false, timeout: 5)) { error in
            XCTAssertFalse(error.localizedDescription.contains("do-not-log-this"))
            XCTAssertTrue(error.localizedDescription.contains("[redacted]"))
        }
    }

    func testNoticesUnexpectedOwnedServerExit() throws {
        let manager = ServerManager(environment: ["FAKE_DSH_MODE": "exit-later"])
        let settings = LauncherSettings(dshPath: fixture.path, workspacePath: NSTemporaryDirectory())
        let connection = try manager.connect(settings: settings, discoverExisting: false, timeout: 5)
        XCTAssertTrue(connection.isOwned)
        for _ in 0..<30 where manager.isOwnedProcessRunning {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(manager.isOwnedProcessRunning)
        manager.stop()
    }
}
