import Foundation

struct Worktree: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var repoId: UUID
    /// Absolute file URL to this worktree's working directory.
    /// NOTE: Persisted as absolute. Same machine-portability caveat as Repo.root.
    var path: URL
    var branch: String
    var displayName: String
    var createdAt: Date
    var lastUsedAt: Date
    var setupCommands: [String]

    init(
        id: UUID = UUID(),
        repoId: UUID,
        path: URL,
        branch: String,
        displayName: String,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        setupCommands: [String] = []
    ) {
        self.id = id
        self.repoId = repoId
        self.path = path
        self.branch = branch
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.setupCommands = setupCommands
    }
}
