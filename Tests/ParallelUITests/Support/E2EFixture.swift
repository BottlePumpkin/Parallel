import Foundation
import XCTest

/// Builds isolated on-disk fixtures for a UI test: a temp git repo, optional
/// real worktrees, an isolated support dir, a seed JSON file, and a probe-file
/// path used to prove the PTY is live. Call `cleanup()` from a `defer`.
struct E2EFixture {
    let rootDir: URL
    let supportDir: URL
    let seedFile: URL
    let probeFile: URL

    static func make() throws -> E2EFixture {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parallel-e2e-\(UUID().uuidString)", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return E2EFixture(
            rootDir: base,
            supportDir: support,
            seedFile: base.appendingPathComponent("seed.json"),
            probeFile: base.appendingPathComponent("probe.txt")
        )
    }

    /// `git init -b main` + identity + an empty initial commit so that
    /// `git worktree add ... main` has a base to branch from.
    @discardableResult
    func makeRepo(named name: String) throws -> URL {
        let repo = rootDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], in: repo)
        try git(["config", "user.email", "e2e@example.com"], in: repo)
        try git(["config", "user.name", "E2E Bot"], in: repo)
        try git(["commit", "--allow-empty", "-m", "init"], in: repo)
        return repo
    }

    /// Real `git worktree add -b <branch> <path> main`. Returns the worktree dir.
    @discardableResult
    func addWorktree(repo: URL, branch: String, dirName: String) throws -> URL {
        let wt = rootDir.appendingPathComponent(dirName, isDirectory: true)
        try git(["worktree", "add", "-b", branch, wt.path, "main"], in: repo)
        return wt
    }

    func writeSeed(_ json: String) throws {
        try Data(json.utf8).write(to: seedFile)
    }

    func cleanup() { try? FileManager.default.removeItem(at: rootDir) }

    /// Path to a real git binary that does not call xcrun (which is blocked in the
    /// App Sandbox that wraps the XCUITest runner). Prefer Homebrew/CLT installations
    /// over the /usr/bin stub, which delegates to xcrun on macOS.
    private static let gitExecutable: String = {
        let candidates = [
            "/opt/homebrew/bin/git",          // Homebrew (Apple Silicon / Intel)
            "/usr/local/bin/git",             // Homebrew (Intel legacy)
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",  // Xcode CLT
            "/usr/bin/git"                    // System stub – last resort
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "/usr/bin/git"
    }()

    @discardableResult
    private func git(_ args: [String], in dir: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: E2EFixture.gitExecutable)
        p.arguments = args
        p.currentDirectoryURL = dir
        // Minimal environment: suppress credential helpers and system config
        // (both can trigger xcrun inside the sandbox).
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "git", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed:\n\(out)"])
        }
        return out
    }
}

extension XCUIApplication {
    /// Launch the app in hermetic e2e mode pointed at this fixture.
    func launchE2E(fixture: E2EFixture) {
        launchEnvironment["PARALLEL_E2E"] = "1"
        launchEnvironment["PARALLEL_SUPPORT_DIR"] = fixture.supportDir.path
        launchEnvironment["PARALLEL_E2E_SEED"] = fixture.seedFile.path
        launch()
    }
}
