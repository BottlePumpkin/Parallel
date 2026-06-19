import XCTest
import Foundation
@testable import Parallel

final class TestSeedTests: XCTestCase {
    private func tempStore() throws -> WorkspaceStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WorkspaceStore(directory: dir)
    }

    func testApplyInsertsReposAndWorktrees() throws {
        let store = try tempStore()
        let spec = TestSeed.Spec(
            repos: [.init(root: "/tmp/demo", displayName: "demo")],
            worktrees: [.init(repoIndex: 0, path: "/tmp/demo/wt", branch: "feature/x", displayName: "feature-x")]
        )
        TestSeed.apply(spec, to: store)

        XCTAssertEqual(store.repos.count, 1)
        XCTAssertEqual(store.repos.first?.displayName, "demo")
        XCTAssertEqual(store.worktrees.count, 1)
        XCTAssertEqual(store.worktrees.first?.branch, "feature/x")
        XCTAssertEqual(store.worktrees.first?.repoId, store.repos.first?.id)
    }

    func testApplyIsNoOpWhenStoreNotEmpty() throws {
        let store = try tempStore()
        store.addRepo(Repo(root: URL(fileURLWithPath: "/tmp/pre"), displayName: "pre"))
        let spec = TestSeed.Spec(repos: [.init(root: "/tmp/demo", displayName: "demo")], worktrees: [])
        TestSeed.applyIfNeeded(to: store, env: ["PARALLEL_E2E_SEED": "/does/not/matter"])
        XCTAssertEqual(store.repos.count, 1)
        XCTAssertEqual(store.repos.first?.displayName, "pre")
    }
}
