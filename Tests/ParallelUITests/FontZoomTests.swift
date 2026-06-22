import XCTest

/// Drives the ⌘+ / ⌘- / ⌘0 font commands through the real menu and asserts the
/// size the app applies, read back from the `e2e.terminalFontSize` probe. The
/// rendered SwiftTerm glyphs aren't in the AX tree, so the probe is the
/// load-bearing signal that the size actually changed.
final class FontZoomTests: XCTestCase {
    func testFontZoomIncreaseAndReset() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let app = XCUIApplication()
        app.launchE2E(fixture: fx)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let probe = app.staticTexts["e2e.terminalFontSize"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "font-size probe should be mounted in e2e")
        expectValue(probe, toEqual: "13", timeout: 5)   // default

        clickTerminalMenuItem(app, "Increase Font Size")
        expectValue(probe, toEqual: "14", timeout: 5)

        clickTerminalMenuItem(app, "Increase Font Size")
        expectValue(probe, toEqual: "15", timeout: 5)

        clickTerminalMenuItem(app, "Decrease Font Size")
        expectValue(probe, toEqual: "14", timeout: 5)

        clickTerminalMenuItem(app, "Reset Font Size")
        expectValue(probe, toEqual: "13", timeout: 5)

        app.terminate()
    }

    /// Open the Terminal menu and click one of its items by title.
    private func clickTerminalMenuItem(_ app: XCUIApplication, _ title: String) {
        let terminalMenu = app.menuBars.menuBarItems["Terminal"]
        XCTAssertTrue(terminalMenu.waitForExistence(timeout: 5), "Terminal menu should exist")
        terminalMenu.click()
        let item = app.menuBars.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "menu item \(title) should exist")
        item.click()
    }
}
