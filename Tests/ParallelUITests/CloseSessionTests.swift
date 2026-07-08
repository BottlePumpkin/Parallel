import XCTest

/// Issue #19: ⌘W must close only the active shell tab — never the whole worktree
/// (all tabs) and never the window/app. This drives the real ⌘W key equivalent
/// (not a menu click) so it exercises the full routing, including the fix that
/// strips AppKit's competing standard Close ⌘W. Tab count is read from the
/// `e2e.runningSessionCount` probe; the window staying alive proves ⌘W did not
/// quit the single-window app.
final class CloseSessionTests: XCTestCase {
    func testCommandWClosesOnlyActiveTabAndKeepsAppAlive() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        let alpha = try fx.addWorktree(repo: repo, branch: "alpha", dirName: "alpha")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[
           {"repoIndex":0,"path":"\(alpha.path)","branch":"alpha","displayName":"alpha"}
         ]}
        """)

        let app = XCUIApplication()
        app.launchE2E(fixture: fx)

        let alphaRow = app.staticTexts["alpha"]
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 15), "seeded 'alpha' row should be visible")

        let count = app.staticTexts["e2e.runningSessionCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))

        // One live session for the worktree…
        alphaRow.click()
        expectValue(count, toEqual: "1", timeout: 15)

        // …then a second tab, so a whole-worktree close would drop to 0.
        clickTerminalMenuItem(app, "New Tab")
        expectValue(count, toEqual: "2", timeout: 10)

        // ⌘W closes exactly one tab (2 → 1), not the worktree (would be 0),
        // and the window survives (app did not quit).
        app.typeKey("w", modifierFlags: .command)
        expectValue(count, toEqual: "1", timeout: 10)
        XCTAssertTrue(app.windows.firstMatch.exists, "⌘W must not close the window / quit the app")

        // Closing the last tab empties the worktree but still must not quit.
        app.typeKey("w", modifierFlags: .command)
        expectValue(count, toEqual: "0", timeout: 10)
        XCTAssertTrue(app.windows.firstMatch.exists, "⌘W on the last tab must not quit the app")

        // The empty worktree offers a one-click resume rather than tearing down.
        XCTAssertTrue(app.buttons["Open Tab"].waitForExistence(timeout: 5),
                      "empty worktree should show the 'Open Tab' placeholder")

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
