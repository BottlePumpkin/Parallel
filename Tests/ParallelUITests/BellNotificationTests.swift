import XCTest

/// Issue #12: a real terminal bell in a BACKGROUND session raises an unread
/// in-app notification; opening the popover marks it read; tapping the row
/// navigates to that worktree. The bell is produced by the *real* PTY path — the
/// seeded "alpha" worktree runs `printf '\a'` a few seconds after its shell
/// starts, by which point we've switched to "beta", so alpha is backgrounded.
final class BellNotificationTests: XCTestCase {
    func testBackgroundBellRaisesNotificationAndNavigates() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        let alpha = try fx.addWorktree(repo: repo, branch: "alpha", dirName: "alpha")
        let beta  = try fx.addWorktree(repo: repo, branch: "beta",  dirName: "beta")
        // `\\\\a` in this Swift literal → `\\a` in the seed JSON → `\a` after JSON
        // decode → the shell runs `printf '\a'`, emitting a BEL (0x07).
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[
           {"repoIndex":0,"path":"\(alpha.path)","branch":"alpha","displayName":"alpha","setupCommands":["sleep 3; printf '\\\\a'"]},
           {"repoIndex":0,"path":"\(beta.path)","branch":"beta","displayName":"beta"}
         ]}
        """)

        let app = XCUIApplication()
        app.launchE2E(fixture: fx)

        let alphaRow = app.staticTexts["alpha"]
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 15))
        let count = app.staticTexts["e2e.runningSessionCount"]
        let awt = app.staticTexts["e2e.activeWorktreeId"]
        let unread = app.staticTexts["e2e.unreadNotificationCount"]
        XCTAssertTrue(unread.waitForExistence(timeout: 5))

        // Start alpha (its bell is now scheduled), then switch to beta so alpha
        // is backgrounded before the bell fires.
        alphaRow.click()
        expectValue(count, toEqual: "1", timeout: 15)
        let alphaId = awt.value as? String
        app.staticTexts["beta"].click()
        expectValue(count, toEqual: "2", timeout: 15)

        // alpha's delayed bell fires while backgrounded → one unread notification.
        expectValue(unread, toEqual: "1", timeout: 15)

        // Opening the popover marks all read; tapping the row navigates to alpha.
        // `.firstMatch`: SwiftUI surfaces the toolbar button twice in the AX tree.
        app.buttons["toolbar.notifications"].firstMatch.click()
        let row = app.buttons["notificationRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        expectValue(unread, toEqual: "0", timeout: 5)
        row.click()
        expectValue(awt, toEqual: alphaId ?? "", timeout: 10)

        app.terminate()
    }
}
