import Foundation
import XCTest
@testable import LauncherCore

final class ServerDiscoveryTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../fixtures/dsh").standardizedFileURL
    }

    func testAttachesToTokenServerUsingItsOpenLog() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: log) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = fixture
        process.arguments = ["web", "--no-open", "--port", "0"]
        process.environment = ProcessInfo.processInfo.environment.merging(["FAKE_DSH_MODE": "token"]) { _, new in new }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }

        var connection: ServerConnection?
        for _ in 0..<30 {
            connection = try? ServerDiscovery.find(onlyPID: process.processIdentifier)
            if connection != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(connection?.url.query, "token=test-secret")
        XCTAssertEqual(connection?.isOwned, false)
        XCTAssertTrue(process.isRunning)
    }

    func testCommandCheckRejectsLookalikes() {
        XCTAssertTrue(ServerDiscovery.isDshCommand("node /tmp/@deepseek-ai/dsh/lib/bin.js web --port 0"))
        XCTAssertTrue(ServerDiscovery.isDshCommand("/tmp/fixtures/dsh web --port 0"))
        XCTAssertFalse(ServerDiscovery.isDshCommand("vim dsh-notes.txt"))
        XCTAssertFalse(ServerDiscovery.isDshCommand("node /tmp/dsh/lib/bin.js inspect"))
    }

    func testTokenServerWithoutReadableLogUsesPreferredURL() throws {
        let portFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: portFile) }
        let process = Process()
        process.executableURL = fixture
        process.arguments = ["web", "--no-open", "--port", "0"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "FAKE_DSH_MODE": "token", "FAKE_DSH_PORT_FILE": portFile.path
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        for _ in 0..<30 where !FileManager.default.fileExists(atPath: portFile.path) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let port = try XCTUnwrap(Int(String(contentsOf: portFile, encoding: .utf8)))
        XCTAssertThrowsError(try ServerDiscovery.find(onlyPID: process.processIdentifier)) { error in
            guard case ServerError.tokenRequired = error else { return XCTFail("Expected tokenRequired") }
        }
        let preferred = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/?token=test-secret"))
        let connection = try ServerDiscovery.find(preferredURL: preferred, onlyPID: process.processIdentifier)
        XCTAssertEqual(connection?.url, preferred)
        XCTAssertFalse(connection?.isOwned ?? true)
    }
}
