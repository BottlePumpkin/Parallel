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

    func testSetupCommandsDecodeAndApply() throws {
        // The bell e2e (issue #12) drives a real terminal bell through a seeded
        // setup command, so the seed must carry setupCommands onto the Worktree.
        let json = """
        {"repos":[{"root":"/tmp/demo","displayName":"demo"}],
         "worktrees":[{"repoIndex":0,"path":"/tmp/demo/wt","branch":"alpha","displayName":"alpha","setupCommands":["printf '\\\\a'"]}]}
        """
        let spec = try JSONDecoder().decode(TestSeed.Spec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.worktrees.first?.setupCommands, ["printf '\\a'"])

        let store = try tempStore()
        TestSeed.apply(spec, to: store)
        XCTAssertEqual(store.worktrees.first?.setupCommands, ["printf '\\a'"])
    }

    func testMissingSetupCommandsDefaultsToEmpty() throws {
        let store = try tempStore()
        let spec = TestSeed.Spec(
            repos: [.init(root: "/tmp/demo", displayName: "demo")],
            worktrees: [.init(repoIndex: 0, path: "/tmp/demo/wt", branch: "main", displayName: "x")]
        )
        TestSeed.apply(spec, to: store)
        XCTAssertEqual(store.worktrees.first?.setupCommands, [])
    }

    func testOutOfBoundsRepoIndexIsSkipped() throws {
        let store = try tempStore()
        let spec = TestSeed.Spec(
            repos: [.init(root: "/tmp/demo", displayName: "demo")],
            worktrees: [.init(repoIndex: 99, path: "/tmp/demo/wt", branch: "main", displayName: "x")]
        )
        TestSeed.apply(spec, to: store)
        XCTAssertEqual(store.repos.count, 1)
        XCTAssertEqual(store.worktrees.count, 0)  // out-of-bounds entry dropped
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
