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

    func list(in repoRoot: URL) throws -> [Entry] {
        let r = try GitCLI.run(["worktree", "list", "--porcelain"], in: repoRoot)
        guard r.exitCode == 0 else {
            throw ServiceError.gitFailed(stderr: r.stderr, exitCode: r.exitCode)
        }
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
        let args: [String]
        if createBranch {
            args = ["worktree", "add", "-b", branch, path.path, base]
        } else {
            args = ["worktree", "add", path.path, branch]
        }
        let r = try GitCLI.run(args, in: repoRoot)
        guard r.exitCode == 0 else {
            throw ServiceError.gitFailed(stderr: r.stderr, exitCode: r.exitCode)
        }
    }
}
