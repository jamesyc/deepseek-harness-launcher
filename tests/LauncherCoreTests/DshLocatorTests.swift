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

        let launch = try DshLocator.resolve(configuredPath: nil, searchDirectories: [directory.path])
        XCTAssertEqual(launch.executableURL.path, dsh.path)
        XCTAssertEqual(launch.argumentsPrefix, [])
        let configured = try DshLocator.resolve(configuredPath: dsh.path, searchDirectories: [])
        XCTAssertEqual(configured.executableURL.path, dsh.path)
        XCTAssertEqual(configured.argumentsPrefix, [])
        XCTAssertTrue(configured.environment.isEmpty)
    }

    func testMissingOrInvalidConfiguredExecutableFails() {
        XCTAssertThrowsError(try DshLocator.resolve(configuredPath: nil, searchDirectories: []))
        XCTAssertThrowsError(try DshLocator.resolve(configuredPath: "/definitely/not/dsh", searchDirectories: []))
    }

    func testMiseLauncherActivatesNodeWithFinderPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("bin")
        let runtime = root.appendingPathComponent("runtime")
        let installed = root.appendingPathComponent("installed")
        for directory in [bin, runtime, installed] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let dsh = installed.appendingPathComponent("dsh")
        let node = runtime.appendingPathComponent("node")
        let mise = bin.appendingPathComponent("mise")
        try "".write(to: root.appendingPathComponent("cwd-marker"), atomically: true, encoding: .utf8)
        try "#!/usr/bin/env node\n".write(to: dsh, atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho activated-node\n".write(to: node, atomically: true, encoding: .utf8)
        let miseScript = """
        #!/bin/sh
        [ "$MISE_AUTO_INSTALL" = false ] && [ "$MISE_EXEC_AUTO_INSTALL" = false ] || exit 2
        [ -f ./cwd-marker ] || exit 3
        if [ "$1" = which ]; then echo '\(dsh.path)'; exit 0; fi
        if [ "$1" = exec ] && [ "$2" = -- ]; then
            shift 2
            PATH='\(runtime.path)':$PATH
            export PATH
            exec "$@"
        fi
        exit 4
        """
        try miseScript.write(to: mise, atomically: true, encoding: .utf8)
        for file in [dsh, node, mise] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }

        let launch = try DshLocator.resolve(configuredPath: nil, searchDirectories: [bin.path],
                                            workingDirectory: root)
        XCTAssertEqual(launch.executableURL.path, mise.path)
        XCTAssertEqual(launch.argumentsPrefix, ["exec", "--", dsh.path])
        let child = Process()
        let output = Pipe()
        child.executableURL = launch.executableURL
        child.arguments = launch.argumentsPrefix + ["--version"]
        child.currentDirectoryURL = root
        child.environment = ["PATH": "/usr/bin:/bin"].merging(launch.environment) { _, new in new }
        child.standardOutput = output
        try child.run()
        let result = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus, 0)
        XCTAssertEqual(result?.trimmingCharacters(in: .whitespacesAndNewlines), "activated-node")
    }
}
