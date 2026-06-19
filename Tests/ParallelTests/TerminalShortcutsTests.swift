import XCTest
@testable import Parallel

final class TerminalShortcutsTests: XCTestCase {

    // MARK: - adjacentTabIndex (tab cycling math)

    func test_adjacentTabIndex_forward_wraps_at_end() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 2, count: 3, forward: true), 0)
    }

    func test_adjacentTabIndex_forward_advances() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 3, forward: true), 1)
    }

    func test_adjacentTabIndex_backward_wraps_at_start() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 3, forward: false), 2)
    }

    func test_adjacentTabIndex_backward_retreats() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 2, count: 3, forward: false), 1)
    }

    func test_adjacentTabIndex_single_tab_stays() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 1, forward: true), 0)
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 1, forward: false), 0)
    }

    func test_adjacentTabIndex_no_tabs_isNil() {
        XCTAssertNil(SessionManager.adjacentTabIndex(from: 0, count: 0, forward: true))
    }

    // MARK: - orderedWorktrees (sidebar-visible order = the ⌘⌥1–9 fix)

    func test_orderedWorktrees_groups_by_repo_in_sidebar_order() {
        let store = WorkspaceStore(directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        let repoA = Repo(root: URL(fileURLWithPath: "/tmp/a"), displayName: "A")
        let repoB = Repo(root: URL(fileURLWithPath: "/tmp/b"), displayName: "B")
        store.repos = [repoA, repoB]
        // Raw array interleaved across repos (the bug scenario): A1, B1, A2.
        let a1 = Worktree(repoId: repoA.id, path: URL(fileURLWithPath: "/tmp/a/1"), branch: "a1", displayName: "a1")
        let b1 = Worktree(repoId: repoB.id, path: URL(fileURLWithPath: "/tmp/b/1"), branch: "b1", displayName: "b1")
        let a2 = Worktree(repoId: repoA.id, path: URL(fileURLWithPath: "/tmp/a/2"), branch: "a2", displayName: "a2")
        store.worktrees = [a1, b1, a2]

        // Sidebar shows A:{a1,a2} then B:{b1} → visible order a1,a2,b1.
        XCTAssertEqual(store.orderedWorktrees.map(\.id), [a1.id, a2.id, b1.id])
        // Raw index 1 was b1 (the bug); visible index 1 is now a2.
        XCTAssertEqual(store.orderedWorktrees[1].id, a2.id)
    }
}
