import Foundation

struct Repo: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
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
