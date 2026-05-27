import XCTest
@testable import Parallel

final class WorktreeServiceTests: XCTestCase {
    var repoRoot: URL!

    override func setUpWithError() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        repoRoot = tmp
        _ = try GitCLI.run(["init", "-q", "-b", "main"], in: tmp)
        _ = try GitCLI.run(["config", "user.email", "t@t"], in: tmp)
        _ = try GitCLI.run(["config", "user.name", "t"], in: tmp)
        try "hi".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try GitCLI.run(["add", "."], in: tmp)
        _ = try GitCLI.run(["commit", "-qm", "init"], in: tmp)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoRoot)
    }

    func test_list_freshRepo_returnsMainWorktree() throws {
        let svc = WorktreeService()
        let entries = try svc.list(in: repoRoot)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].branch, "main")
        XCTAssertEqual(entries[0].path.standardizedFileURL, repoRoot.standardizedFileURL)
    }

    // MARK: - parseList unit tests (no git process required)

    func test_parseList_empty_returnsEmpty() {
        XCTAssertEqual(WorktreeService.parseList("").count, 0)
    }

    func test_parseList_singleBlock_noTrailingBlankLine() {
        let raw = """
        worktree /tmp/main
        HEAD abc123
        branch refs/heads/main
        """
        let entries = WorktreeService.parseList(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].branch, "main")
        XCTAssertEqual(entries[0].head, "abc123")
    }

    func test_parseList_multipleBlocks_trailingBlankLine() {
        let raw = "worktree /tmp/main\nHEAD a1\nbranch refs/heads/main\n\nworktree /tmp/wt\nHEAD a2\nbranch refs/heads/feat-x\n\n"
        let entries = WorktreeService.parseList(raw)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].branch, "main")
        XCTAssertEqual(entries[1].branch, "feat-x")
    }

    func test_parseList_detachedHEAD_setsSentinel() {
        let raw = "worktree /tmp/d\nHEAD deadbeef\ndetached\n"
        let entries = WorktreeService.parseList(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].branch, "(detached)")
    }

    func test_parseList_bareRepo_setsSentinel() {
        let raw = "worktree /tmp/b\nHEAD a1\nbare\n"
        let entries = WorktreeService.parseList(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].branch, "(bare)")
    }

    func test_parseList_ignoresUnknownAnnotations() {
        let raw = "worktree /tmp/l\nHEAD a1\nbranch refs/heads/main\nlocked\nprunable\n"
        let entries = WorktreeService.parseList(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].branch, "main")
    }

    func test_add_createsNewBranchAndWorktree() throws {
        let svc = WorktreeService()
        let dest = repoRoot.appendingPathComponent(".claude/worktrees/feat-x")
        try svc.add(repoRoot: repoRoot, branch: "feat/x", base: "main", path: dest, createBranch: true)

        let entries = try svc.list(in: repoRoot)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.branch == "feat/x" })
    }

    func test_add_existingPath_throws() throws {
        let svc = WorktreeService()
        let dest = repoRoot.appendingPathComponent(".claude/worktrees/feat-y")
        try svc.add(repoRoot: repoRoot, branch: "feat/y", base: "main", path: dest, createBranch: true)
        XCTAssertThrowsError(try svc.add(repoRoot: repoRoot, branch: "feat/y", base: "main", path: dest, createBranch: true))
    }
}
