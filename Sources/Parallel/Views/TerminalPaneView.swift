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
                let entry = sessionManager.session(for: wt.id)
                if let entry, case .running = entry.session.state {
                    TerminalContainer(worktree: wt)
                        .id(wt.id)
                } else {
                    deadSessionPlaceholder(for: wt)
                }
            } else {
                emptyPlaceholder
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Select a worktree").foregroundStyle(.secondary)
            Text("Note: terminal sessions don't persist across app restarts.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deadSessionPlaceholder(for wt: Worktree) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Session ended").font(.headline)
            Text(wt.path.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
            Button("Restart Session") {
                sessionManager.restartSession(for: wt, setupCommands: wt.setupCommands)
            }
            .keyboardShortcut(.defaultAction)
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

    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
