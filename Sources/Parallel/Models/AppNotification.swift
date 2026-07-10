import Foundation

/// One entry in the in-app notification list (issue #12).
struct AppNotification: Identifiable, Equatable {
    enum Kind: Equatable { case needsAttention, sessionEnded }

    let id: UUID
    let kind: Kind
    let worktreeId: UUID
    let sessionId: UUID
    let worktreeName: String
    let branch: String
    let tabLabel: String
    let date: Date
    var isRead: Bool

    init(kind: Kind, worktreeId: UUID, sessionId: UUID, worktreeName: String,
         branch: String, tabLabel: String, date: Date = Date(),
         isRead: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.worktreeId = worktreeId
        self.sessionId = sessionId
        self.worktreeName = worktreeName
        self.branch = branch
        self.tabLabel = tabLabel
        self.date = date
        self.isRead = isRead
    }
}

/// The worktree/tab a notification points at; consumed by the view layer to
/// navigate on row tap or banner click.
struct NavigationTarget: Equatable {
    let worktreeId: UUID
    let sessionId: UUID
}
