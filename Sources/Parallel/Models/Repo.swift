import Foundation

struct Repo: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    /// Absolute file URL to the repository root.
    /// NOTE: Persisted as an absolute path. If the user renames their home
    /// directory or moves workspace.json across machines, this becomes stale
    /// with no automatic recovery. Acceptable for v1 personal use.
    var root: URL
    var displayName: String
    var worktreeBaseDir: String          // 기본 ".claude/worktrees", repo.root 기준 상대경로
    var defaultSetupCommands: [String]

    init(
        id: UUID = UUID(),
        root: URL,
        displayName: String,
        worktreeBaseDir: String = ".claude/worktrees",
        defaultSetupCommands: [String] = []
    ) {
        self.id = id
        self.root = root
        self.displayName = displayName
        self.worktreeBaseDir = worktreeBaseDir
        self.defaultSetupCommands = defaultSetupCommands
    }
}
