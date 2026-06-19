import XCTest

final class LaunchSmokeTests: XCTestCase {
    func testAppLaunchesAndShowsWindow() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let app = XCUIApplication()
        app.launchE2E(fixture: fx)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        app.terminate()
    }
}
