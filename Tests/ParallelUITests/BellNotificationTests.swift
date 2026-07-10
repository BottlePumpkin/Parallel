import XCTest

/// Issue #12: a real terminal bell in a BACKGROUND session raises an unread
/// in-app notification; opening the popover marks it read; tapping the row
/// navigates to that worktree. Drives the full bell → delegate → store → UI path
/// (the BEL is fed to a non-visible SwiftTerm view via an e2e affordance).
final class BellNotificationTests: XCTestCase {
    func testBackgroundBellRaisesNotificationAndNavigates() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        let alpha = try fx.addWorktree(repo: repo, branch: "alpha", dirName: "alpha")
        let beta  = try fx.addWorktree(repo: repo, branch: "beta",  dirName: "beta")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[
           {"repoIndex":0,"path":"\(alpha.path)","branch":"alpha","displayName":"alpha"},
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

        // Start alpha, then beta — alpha ends up backgrounded, beta visible.
        alphaRow.click()
        expectValue(count, toEqual: "1", timeout: 15)
        let alphaId = awt.value as? String
        app.staticTexts["beta"].click()
        expectValue(count, toEqual: "2", timeout: 15)

        // Feed a real BEL to the backgrounded alpha session.
        app.buttons["e2e.emitBackgroundBell"].click()
        expectValue(unread, toEqual: "1", timeout: 10)

        // Open the popover (marks read) and tap the row to navigate back to alpha.
        app.buttons["toolbar.notifications"].click()
        let row = app.buttons["notificationRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        expectValue(unread, toEqual: "0", timeout: 5)   // mark-all-read on open
        row.click()
        expectValue(awt, toEqual: alphaId ?? "", timeout: 10)   // navigated to alpha

        app.terminate()
    }
}
