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
                // ensureSession is idempotent — returns existing entry if
                // already running, or forks a new PTY for first-visit
                // worktrees. Called from body so any path change auto-
                // creates a session.
                let entry = sessionManager.ensureSession(
                    for: wt, setupCommands: wt.setupCommands
                )
                if let entry, case .running = entry.session.state {
                    // Mount every running session's NSView continuously and
                    // toggle visibility. Re-parenting SwiftTerm's NSView on
                    // worktree switches corrupted its scroll/layout cache,
                    // so we never detach — only flip opacity.
                    activeStack(currentId: wt.id)
                } else {
                    deadSessionPlaceholder(for: wt)
                }
            } else {
                emptyPlaceholder
            }
        }
    }

    private func activeStack(currentId: UUID) -> some View {
        ZStack {
            ForEach(sessionManager.allRunningSessions, id: \.session.id) { entry in
                MountedTerminalView(terminalView: entry.terminalView)
                    .opacity(entry.session.worktreeId == currentId ? 1 : 0)
                    .allowsHitTesting(entry.session.worktreeId == currentId)
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

/// Wraps a single SwiftTerm NSView. Mounts the exact instance passed in;
/// updateNSView is a no-op because the wrapped view is owned by SessionManager
/// and must outlive any SwiftUI view tree changes.
private struct MountedTerminalView: NSViewRepresentable {
    let terminalView: TerminalView

    func makeNSView(context: Context) -> TerminalView { terminalView }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
