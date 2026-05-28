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
    /// MRU list of base branches selected when creating worktrees.
    /// Shown at the top of the Base dropdown in NewWorktreeSheet so the
    /// user can pick frequently-used bases (e.g. origin/develop) without
    /// scrolling through every remote-tracking ref.
    var recentBases: [String]

    init(
        id: UUID = UUID(),
        root: URL,
        displayName: String,
        worktreeBaseDir: String = ".claude/worktrees",
        defaultSetupCommands: [String] = [],
        recentBases: [String] = []
    ) {
        self.id = id
        self.root = root
        self.displayName = displayName
        self.worktreeBaseDir = worktreeBaseDir
        self.defaultSetupCommands = defaultSetupCommands
        self.recentBases = recentBases
    }

    // Custom Codable so adding `recentBases` doesn't break existing
    // workspace.json files (the field is decoded as [] when missing).
    private enum CodingKeys: String, CodingKey {
        case id, root, displayName, worktreeBaseDir, defaultSetupCommands, recentBases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.root = try c.decode(URL.self, forKey: .root)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.worktreeBaseDir = try c.decode(String.self, forKey: .worktreeBaseDir)
        self.defaultSetupCommands = try c.decode([String].self, forKey: .defaultSetupCommands)
        self.recentBases = (try? c.decode([String].self, forKey: .recentBases)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(root, forKey: .root)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(worktreeBaseDir, forKey: .worktreeBaseDir)
        try c.encode(defaultSetupCommands, forKey: .defaultSetupCommands)
        try c.encode(recentBases, forKey: .recentBases)
    }
}
