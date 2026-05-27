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
}
