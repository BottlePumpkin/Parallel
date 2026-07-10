import XCTest
@testable import Parallel

/// Issue #12: suppress the macOS banner only when the belling session is the one
/// the user is already looking at (visible) AND the app is frontmost.
final class NotificationBannerTests: XCTestCase {
    func test_truthTable() {
        XCTAssertFalse(NotificationBanner.shouldBanner(appActive: true,  sessionVisible: true))
        XCTAssertTrue( NotificationBanner.shouldBanner(appActive: true,  sessionVisible: false))
        XCTAssertTrue( NotificationBanner.shouldBanner(appActive: false, sessionVisible: true))
        XCTAssertTrue( NotificationBanner.shouldBanner(appActive: false, sessionVisible: false))
    }
}
