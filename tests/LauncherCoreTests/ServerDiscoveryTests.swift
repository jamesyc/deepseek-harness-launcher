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
        let process = Process()
        process.executableURL = fixture
        process.arguments = ["web", "--no-open", "--port", "0"]
        process.environment = ProcessInfo.processInfo.environment.merging(["FAKE_DSH_MODE": "token"]) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let line = try XCTUnwrap(String(data: output.fileHandleForReading.availableData, encoding: .utf8))
        let port = try XCTUnwrap(ServerURL.fromStartupLine(line)?.port)
        XCTAssertThrowsError(try ServerDiscovery.find(onlyPID: process.processIdentifier)) { error in
            guard case ServerError.tokenRequired = error else { return XCTFail("Expected tokenRequired") }
        }
        let preferred = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/?token=test-secret"))
        let connection = try ServerDiscovery.find(preferredURL: preferred, onlyPID: process.processIdentifier)
        XCTAssertEqual(connection?.url, preferred)
        XCTAssertFalse(connection?.isOwned ?? true)
    }

    func testFindsIPv6OnlyServer() throws {
        let process = Process()
        process.executableURL = fixture
        process.arguments = ["web", "--no-open", "--port", "0"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "FAKE_DSH_MODE": "bare", "FAKE_DSH_HOST": "::1"
        ]) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        _ = output.fileHandleForReading.availableData

        let connection = try ServerDiscovery.find(onlyPID: process.processIdentifier)
        XCTAssertEqual(connection?.url.host, "::1")
        XCTAssertFalse(connection?.isOwned ?? true)
    }
}
