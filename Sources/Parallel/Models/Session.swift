import Foundation

enum SessionState: Equatable {
    case running
    case exited(code: Int32)
}

/// SwiftTerm view를 SessionManager가 보유하므로 여기선 메타만.
final class Session: Identifiable, Equatable {
    let id: UUID
    let worktreeId: UUID
    var pid: pid_t
    var state: SessionState

    init(id: UUID = UUID(), worktreeId: UUID, pid: pid_t, state: SessionState = .running) {
        self.id = id
        self.worktreeId = worktreeId
        self.pid = pid
        self.state = state
    }

    static func == (lhs: Session, rhs: Session) -> Bool { lhs.id == rhs.id }
}
