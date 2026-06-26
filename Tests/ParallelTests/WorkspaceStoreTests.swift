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

    func test_moveWorktrees_reordersInSection() {
        let store = WorkspaceStore(directory: tempDir)
        let repoA = Repo(root: URL(fileURLWithPath: "/tmp/a"), displayName: "A")
        let repoB = Repo(root: URL(fileURLWithPath: "/tmp/b"), displayName: "B")
        store.addRepo(repoA)
        store.addRepo(repoB)
        let a1 = Worktree(repoId: repoA.id, path: URL(fileURLWithPath: "/tmp/a/1"), branch: "a1", displayName: "a1")
        let a2 = Worktree(repoId: repoA.id, path: URL(fileURLWithPath: "/tmp/a/2"), branch: "a2", displayName: "a2")
        let a3 = Worktree(repoId: repoA.id, path: URL(fileURLWithPath: "/tmp/a/3"), branch: "a3", displayName: "a3")
        let b1 = Worktree(repoId: repoB.id, path: URL(fileURLWithPath: "/tmp/b/1"), branch: "b1", displayName: "b1")
        for wt in [a1, a2, a3, b1] { store.addWorktree(wt) }

        // Move repoA's index 0 (a1) to position 2 (after a3). With SwiftUI
        // semantics that means: target slot in the section after the move is 2.
        store.moveWorktrees(in: repoA.id, from: IndexSet(integer: 0), to: 3)
        let aOrder = store.worktrees.filter { $0.repoId == repoA.id }.map(\.displayName)
        XCTAssertEqual(aOrder, ["a2", "a3", "a1"])
        // RepoB untouched.
        let bOrder = store.worktrees.filter { $0.repoId == repoB.id }.map(\.displayName)
        XCTAssertEqual(bOrder, ["b1"])
    }

    private func seedRepos(_ store: WorkspaceStore, _ names: [String]) -> [Repo] {
        let repos = names.map { Repo(root: URL(fileURLWithPath: "/tmp/\($0)"), displayName: $0) }
        for r in repos { store.addRepo(r) }
        return repos
    }

    func test_moveRepoBefore_reordersAndPersists() throws {
        let store = WorkspaceStore(directory: tempDir)
        let repos = seedRepos(store, ["A", "B", "C"])
        // Move C before A → C, A, B
        store.moveRepo(repos[2].id, before: repos[0].id)
        XCTAssertEqual(store.repos.map(\.displayName), ["C", "A", "B"])

        let reloaded = WorkspaceStore(directory: tempDir)
        try reloaded.load()
        XCTAssertEqual(reloaded.repos.map(\.displayName), ["C", "A", "B"])
    }

    func test_moveRepoBefore_sameId_isNoOp() {
        let store = WorkspaceStore(directory: tempDir)
        let repos = seedRepos(store, ["A", "B"])
        store.moveRepo(repos[0].id, before: repos[0].id)
        XCTAssertEqual(store.repos.map(\.displayName), ["A", "B"])
    }

    func test_moveRepoUp_movesAndClampsAtTop() {
        let store = WorkspaceStore(directory: tempDir)
        let repos = seedRepos(store, ["A", "B", "C"])
        store.moveRepoUp(repos[2].id)            // C up → A, C, B
        XCTAssertEqual(store.repos.map(\.displayName), ["A", "C", "B"])
        store.moveRepoUp(repos[0].id)            // A already first → no-op
        XCTAssertEqual(store.repos.map(\.displayName), ["A", "C", "B"])
    }

    func test_moveRepoDown_movesAndClampsAtBottom() {
        let store = WorkspaceStore(directory: tempDir)
        let repos = seedRepos(store, ["A", "B", "C"])
        store.moveRepoDown(repos[0].id)          // A down → B, A, C
        XCTAssertEqual(store.repos.map(\.displayName), ["B", "A", "C"])
        store.moveRepoDown(repos[2].id)          // C already last → no-op
        XCTAssertEqual(store.repos.map(\.displayName), ["B", "A", "C"])
    }
}
