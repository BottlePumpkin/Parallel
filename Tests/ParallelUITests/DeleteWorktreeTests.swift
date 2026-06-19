import XCTest

final class DeleteWorktreeTests: XCTestCase {
    func testDeleteWorktreeRemovesRow() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        let wt = try fx.addWorktree(repo: repo, branch: "feature/z", dirName: "feature-z")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[{"repoIndex":0,"path":"\(wt.path)","branch":"feature/z","displayName":"feature-z"}]}
        """)

        let app = XCUIApplication()
        app.launchE2E(fixture: fx)

        let row = app.staticTexts["feature-z"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))

        // Select the row, then trigger delete with ⌘⌫.
        row.click()
        app.typeKey(.delete, modifierFlags: .command)

        // Confirm in the delete sheet.
        let confirm = app.buttons["sheet.deleteWorktree.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()

        // The row disappears.
        XCTAssertTrue(waitForDisappearance(row, timeout: 10),
                      "deleted worktree row should be gone")
        app.terminate()
    }
}
