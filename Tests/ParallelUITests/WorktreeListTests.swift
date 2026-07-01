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

        // Worktree row is the load-bearing assertion (proves the seed rendered).
        XCTAssertTrue(app.staticTexts["feature-x"].waitForExistence(timeout: 15),
                      "seeded worktree row should be visible")

        // The visible worktree row above already proves the seeded repo section
        // rendered. We deliberately don't assert on the repo *header* element:
        // it's `.draggable` (repo reordering), which drops its text from the
        // accessibility tree in headless CI, so no query for it is reliable
        // there. Reorder behavior is covered by store-level unit tests instead.
        app.terminate()
    }
}
