import Foundation

final class WorktreeService {

    struct Entry: Equatable {
        var path: URL
        var branch: String
        var head: String       // commit sha
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

    /// `git worktree list --porcelain` 블록 파서.
    /// 각 블록은 빈 줄로 구분. `worktree <path>`, `HEAD <sha>`, `branch refs/heads/<name>` 또는 `detached`.
    static func parseList(_ raw: String) -> [Entry] {
        var entries: [Entry] = []
        let blocks = raw.components(separatedBy: "\n\n")
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
                }
            }
            if let path, let head {
                entries.append(Entry(path: path, branch: branch ?? "(unknown)", head: head))
            }
        }
        return entries
    }
}
