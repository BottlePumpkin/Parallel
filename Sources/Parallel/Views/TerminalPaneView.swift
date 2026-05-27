import SwiftUI
import SwiftTerm
import AppKit

struct TerminalPaneView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    let worktreeId: UUID?

    var body: some View {
        Group {
            if let id = worktreeId, let wt = store.worktree(id: id) {
                TerminalContainer(worktree: wt)
                    .id(wt.id)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(worktreeId == nil ? "Select a worktree" : "No session")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalContainer: NSViewRepresentable {
    @Environment(SessionManager.self) private var sessionManager
    let worktree: Worktree

    func makeNSView(context: Context) -> TerminalView {
        let entry = sessionManager.ensureSession(for: worktree, setupCommands: worktree.setupCommands)
        return entry?.terminalView ?? TerminalView(frame: .zero)
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // .id(wt.id) on parent triggers makeNSView when worktree changes
    }
}
