import XCTest

final class WorktreeListTests: XCTestCase {
    func testSeededWorktreeAppearsInSidebar() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        let wt = try fx.addWorktree(repo: repo, branch: "feature/x", dirName: "feature-x")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[{"repoIndex":0,"path":"\(wt.path)","branch":"feature/x","displayName":"feature-x"}]}
        """)

        let app = XCUIApplication()
        app.launchE2E(fixture: fx)

        // The repo header renders as a PopUpButton (label: repo displayName).
        // The worktree row primary name renders as a StaticText (value: worktree displayName).
        XCTAssertTrue(app.popUpButtons["demo"].waitForExistence(timeout: 15),
                      "repo section header should be visible")
        XCTAssertTrue(app.staticTexts["feature-x"].waitForExistence(timeout: 10),
                      "seeded worktree row should be visible")
        app.terminate()
    }
}
