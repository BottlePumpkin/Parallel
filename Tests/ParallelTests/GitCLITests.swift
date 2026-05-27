import XCTest
@testable import Parallel

final class GitCLITests: XCTestCase {
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

    func test_run_success_returnsStdout() throws {
        let r = try GitCLI.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repoRoot)
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "main")
    }

    func test_run_failure_capturesStderr() throws {
        let r = try GitCLI.run(["nonsense-subcommand"], in: repoRoot)
        XCTAssertNotEqual(r.exitCode, 0)
        XCTAssertFalse(r.stderr.isEmpty)
    }
}
