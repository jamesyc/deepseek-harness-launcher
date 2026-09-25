import AppKit
import XCTest
@testable import LauncherCore

@MainActor
final class WindowManagerTests: XCTestCase {
    func testMultipleWindowsShareOneURLAndLastCloseFiresOnce() throws {
        _ = NSApplication.shared
        let manager = WindowManager()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:3080/?token=test"))
        var lastCloseCount = 0
        manager.onLastWindowClosed = { lastCloseCount += 1 }

        let first = manager.open(url: url)
        let second = manager.newWindow()
        XCTAssertEqual(manager.windowCount, 2)
        XCTAssertEqual(second?.webView.url, url)
        first.window.close()
        XCTAssertEqual(manager.windowCount, 1)
        XCTAssertEqual(lastCloseCount, 0)
        second?.window.close()
        XCTAssertEqual(manager.windowCount, 0)
        XCTAssertEqual(lastCloseCount, 1)
    }

    func testNewWindowBeforeConnectionDoesNothing() {
        _ = NSApplication.shared
        let manager = WindowManager()
        XCTAssertNil(manager.newWindow())
        XCTAssertEqual(manager.windowCount, 0)
    }
}
