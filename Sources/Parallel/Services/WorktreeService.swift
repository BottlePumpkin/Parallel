import Foundation

final class WorktreeService {

    struct Entry: Equatable {
        let path: URL
        let branch: String
        let head: String       // commit sha
    }

    enum ServiceError: LocalizedError {
        case gitFailed(stderr: String, exitCode: Int32)
        var errorDescription: String? {
            switch self {
            case .gitFailed(let s, let c): return "git failed (exit \(c)): \(s)"
            }
        }
    }

    /// Run git in `dir` and require a clean exit. Throws ServiceError.gitFailed
    /// otherwise. Returns the full result so callers can read stdout.
    @discardableResult
    fileprivate func gitOrThrow(_ args: [String], in dir: URL) throws -> GitCLI.Result {
        let r = try GitCLI.run(args, in: dir)
        guard r.exitCode == 0 else {
            throw ServiceError.gitFailed(stderr: r.stderr, exitCode: r.exitCode)
        }
        return r
    }

    func list(in repoRoot: URL) throws -> [Entry] {
        let r = try gitOrThrow(["worktree", "list", "--porcelain"], in: repoRoot)
        return Self.parseList(r.stdout)
    }

    /// Parser for `git worktree list --porcelain`.
    /// Each block separated by a blank line. Recognized lines:
    /// - `worktree <path>`
    /// - `HEAD <sha>`
    /// - `branch refs/heads/<name>` → branch = name
    /// - `detached`                  → branch = "(detached)"
    /// - `bare`                      → branch = "(bare)"
    /// - other lines (`locked`, `prunable`, ...) are ignored.
    static func parseList(_ raw: String) -> [Entry] {
        let blocks = raw
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var entries: [Entry] = []
        for block in blocks {
            var path: URL?
            var branch: String?
            var head: String?
            for line in block.split(separator: "\n", omittingEmptySubsequences: true) {
                let s = String(line)
                if s.hasPrefix("worktree ") {
                    path = URL(fileURLWithPath: String(s.dropFirst("worktree ".count)))
                } else if s.hasPrefix("HEAD ") {
                    head = String(s.dropFirst("HEAD ".count))
                } else if s.hasPrefix("branch refs/heads/") {
                    branch = String(s.dropFirst("branch refs/heads/".count))
                } else if s == "detached" {
                    branch = "(detached)"
                } else if s == "bare" {
                    branch = "(bare)"
                }
                // unknown lines (locked, prunable, ...) ignored on purpose
            }
            if let path, let head {
                entries.append(Entry(path: path, branch: branch ?? "(unknown)", head: head))
            }
        }
        return entries
    }
}

extension WorktreeService {
    /// Create a new worktree.
    /// - createBranch=true:  `git worktree add -b <branch> <path> <base>`
    /// - createBranch=false: `git worktree add <path> <branch>` (check out existing branch)
    func add(repoRoot: URL, branch: String, base: String, path: URL, createBranch: Bool) throws {
        // Ensure parent directory exists (git won't create intermediate parents)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let args: [String] = createBranch
            ? ["worktree", "add", "-b", branch, path.path, base]
            : ["worktree", "add", path.path, branch]
        try gitOrThrow(args, in: repoRoot)
    }
}

extension WorktreeService {
    /// `git worktree remove <path>` (optionally with `--force`).
    func remove(repoRoot: URL, path: URL, force: Bool) throws {
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path.path)
        try gitOrThrow(args, in: repoRoot)
    }

    /// Run `git status --porcelain` and (if upstream is set) `git rev-list` to
    /// populate a `WorktreeStatus`.
    /// - Returns: status with `isDirty`, `changedFiles`, `ahead`, `behind`, `lastCheckedAt`.
    /// - Note: `changedFiles` counts porcelain lines. Merge conflicts emit lines
    ///   per stage, so the count may overshoot during a conflict. `isDirty` is
    ///   still authoritative.
    func status(at path: URL) throws -> WorktreeStatus {
        var out = WorktreeStatus()
        out.lastCheckedAt = Date()

        let porcelain = try gitOrThrow(["status", "--porcelain"], in: path)
        let lines = porcelain.stdout.split(separator: "\n", omittingEmptySubsequences: true)
        out.changedFiles = lines.count
        out.isDirty = !lines.isEmpty

        // ahead/behind only meaningful if upstream is configured; exit ≠ 0 here is fine.
        let counts = try GitCLI.run(
            ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
            in: path
        )
        if counts.exitCode == 0 {
            let parts = counts.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\t")
            if parts.count == 2,
               let ahead = Int(parts[0]),
               let behind = Int(parts[1]) {
                out.ahead = ahead
                out.behind = behind
            }
        }
        return out
    }
}

extension WorktreeService {
    /// Local branch names in the repo, sorted by most-recent commit date.
    /// Used to suggest a base when creating a worktree.
    func branches(in repoRoot: URL) throws -> [String] {
        let r = try gitOrThrow(
            ["for-each-ref", "--sort=-committerdate", "--format=%(refname:short)", "refs/heads/"],
            in: repoRoot
        )
        return r.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension WorktreeService {
    /// `git branch -D <name>` — force delete a local branch.
    /// Returns silently on success; throws ServiceError.gitFailed otherwise.
    func deleteBranch(repoRoot: URL, branch: String) throws {
        try gitOrThrow(["branch", "-D", branch], in: repoRoot)
    }
}
