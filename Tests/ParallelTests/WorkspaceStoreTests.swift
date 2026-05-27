import XCTest
@testable import Parallel

final class WorkspaceStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_initial_state_isEmpty() {
        let store = WorkspaceStore(directory: tempDir)
        XCTAssertTrue(store.repos.isEmpty)
        XCTAssertTrue(store.worktrees.isEmpty)
        XCTAssertNil(store.lastSelectedWorktreeId)
    }

    func test_saveAndLoad_roundTrip() throws {
        let store = WorkspaceStore(directory: tempDir)
        let repo = Repo(root: URL(fileURLWithPath: "/tmp/repo"), displayName: "demo")
        store.addRepo(repo)
        let worktree = Worktree(
            repoId: repo.id,
            path: URL(fileURLWithPath: "/tmp/repo/.claude/worktrees/feat-x"),
            branch: "feat/x",
            displayName: "feat-x"
        )
        store.addWorktree(worktree)
        store.lastSelectedWorktreeId = worktree.id
        try store.save()

        let reloaded = WorkspaceStore(directory: tempDir)
        try reloaded.load()
        XCTAssertEqual(reloaded.repos, [repo])
        XCTAssertEqual(reloaded.worktrees, [worktree])
        XCTAssertEqual(reloaded.lastSelectedWorktreeId, worktree.id)
    }

    func test_load_corruptedFile_quarantinesAndStartsEmpty() throws {
        let file = tempDir.appendingPathComponent("workspace.json")
        try "this is not json".data(using: .utf8)!.write(to: file)

        let store = WorkspaceStore(directory: tempDir)
        try store.load()
        XCTAssertTrue(store.repos.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("workspace.json.corrupted-") })
    }

    func test_removeWorktree_removesIt() throws {
        let store = WorkspaceStore(directory: tempDir)
        let repo = Repo(root: URL(fileURLWithPath: "/tmp/r"), displayName: "r")
        store.addRepo(repo)
        let wt = Worktree(repoId: repo.id, path: URL(fileURLWithPath: "/tmp/r/.claude/worktrees/x"),
                          branch: "x", displayName: "x")
        store.addWorktree(wt)
        store.removeWorktree(id: wt.id)
        XCTAssertTrue(store.worktrees.isEmpty)
    }
}
