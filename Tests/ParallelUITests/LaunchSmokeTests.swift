import XCTest

final class LaunchSmokeTests: XCTestCase {
    func testAppLaunchesAndShowsWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        app.terminate()
    }
}
