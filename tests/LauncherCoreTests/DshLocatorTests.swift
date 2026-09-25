import Foundation
import XCTest
@testable import LauncherCore

final class DshLocatorTests: XCTestCase {
    func testFindsExecutableOnSearchPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dsh = directory.appendingPathComponent("dsh")
        try "#!/bin/sh\nexit 0\n".write(to: dsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dsh.path)

        XCTAssertEqual(try DshLocator.resolve(configuredPath: nil, searchDirectories: [directory.path]).path, dsh.path)
    }

    func testMissingOrInvalidConfiguredExecutableFails() {
        XCTAssertThrowsError(try DshLocator.resolve(configuredPath: nil, searchDirectories: []))
        XCTAssertThrowsError(try DshLocator.resolve(configuredPath: "/definitely/not/dsh", searchDirectories: []))
    }
}
