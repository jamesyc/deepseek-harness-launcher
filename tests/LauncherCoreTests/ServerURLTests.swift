import XCTest
@testable import LauncherCore

final class ServerURLTests: XCTestCase {
    func testParsesTokenAndBareStartupURLs() {
        XCTAssertEqual(ServerURL.fromStartupLine("dsh web: http://127.0.0.1:61307/?token=abc")?.absoluteString,
                       "http://127.0.0.1:61307/?token=abc")
        XCTAssertEqual(ServerURL.fromStartupLine("dsh web: http://[::1]:3080/\r")?.port, 3080)
    }

    func testRejectsRemoteAndMalformedStartupURLs() {
        XCTAssertNil(ServerURL.fromStartupLine("dsh web: https://example.com:443/?token=x"))
        XCTAssertNil(ServerURL.fromStartupLine("dsh web: http://192.168.1.5:3080/"))
        XCTAssertNil(ServerURL.fromStartupLine("dsh web: http://127.0.0.1/"))
        XCTAssertNil(ServerURL.fromStartupLine("not a startup line"))
    }
}
