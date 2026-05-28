import Foundation
import Observation

enum SessionState: Equatable {
    case running
    case exited(code: Int32)
}

/// Per-PTY metadata. `state` is observable so SwiftUI views (sidebar state
/// dot, TerminalPaneView placeholder) re-render when the shell exits.
@Observable
final class Session: Identifiable, Equatable {
    let id: UUID
    let worktreeId: UUID
    let pid: pid_t
    var state: SessionState

    init(id: UUID = UUID(), worktreeId: UUID, pid: pid_t, state: SessionState = .running) {
        self.id = id
        self.worktreeId = worktreeId
        self.pid = pid
        self.state = state
    }

    static func == (lhs: Session, rhs: Session) -> Bool { lhs.id == rhs.id }
}
