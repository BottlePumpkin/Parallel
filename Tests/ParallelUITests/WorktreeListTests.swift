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

        // Repo section header: its AX element type varies across Xcode versions
        // (a popUpButton locally, a different type in CI), so match by label
        // across any element type rather than pinning to one query.
        let repoHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "demo")).firstMatch
        XCTAssertTrue(repoHeader.waitForExistence(timeout: 10),
                      "repo section header should be visible")
        app.terminate()
    }
}
