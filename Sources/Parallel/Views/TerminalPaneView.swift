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
                let active = sessionManager.activeSession(for: wt.id)
                let tabs = sessionManager.sessions(for: wt.id)
                VStack(spacing: 0) {
                    if !tabs.isEmpty {
                        tabBar(for: wt, tabs: tabs, active: active)
                    }
                    if let active, case .running = active.session.state {
                        activeStack(currentSessionId: active.session.id)
                    } else if let active {
                        deadSessionPlaceholder(for: wt, sessionId: active.session.id)
                    } else {
                        emptyTabsPlaceholder(for: wt)
                    }
                }
            } else {
                emptyPlaceholder
            }
        }
        .task(id: worktreeId) {
            if let id = worktreeId, let wt = store.worktree(id: id) {
                await MainActor.run {
                    _ = sessionManager.ensureSession(
                        for: wt, setupCommands: wt.setupCommands
                    )
                }
            }
        }
    }

    // MARK: - Tab bar

    private func tabBar(for worktree: Worktree,
                        tabs: [SessionManager.SessionEntry],
                        active: SessionManager.SessionEntry?) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.element.session.id) { idx, entry in
                tabButton(
                    label: "shell \(idx + 1)",
                    isActive: entry.session.id == active?.session.id,
                    isDead: {
                        if case .exited = entry.session.state { return true }
                        return false
                    }(),
                    select: {
                        sessionManager.setActive(sessionId: entry.session.id, in: worktree.id)
                    },
                    close: {
                        sessionManager.terminate(sessionId: entry.session.id)
                    }
                )
            }
            Button {
                _ = sessionManager.startSession(for: worktree, setupCommands: worktree.setupCommands)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("New tab in this worktree")
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial)
    }

    private func tabButton(label: String,
                           isActive: Bool,
                           isDead: Bool,
                           select: @escaping () -> Void,
                           close: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: select) {
                HStack(spacing: 4) {
                    if isDead {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Text(label).font(.caption)
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderless)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close this tab")
        }
        .padding(.vertical, 2)
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.25) : Color.clear)
        )
    }

    // MARK: - Terminal stack

    /// Continuously-mounted ZStack of every running session's NSView.
    /// Only the currently-active session has opacity 1 and accepts input.
    private func activeStack(currentSessionId: UUID) -> some View {
        ZStack {
            ForEach(sessionManager.allRunningSessions, id: \.session.id) { entry in
                MountedTerminalView(terminalView: entry.terminalView)
                    .opacity(entry.session.id == currentSessionId ? 1 : 0)
                    .allowsHitTesting(entry.session.id == currentSessionId)
            }
        }
    }

    // MARK: - Placeholders

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

    private func emptyTabsPlaceholder(for wt: Worktree) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("No tabs").font(.headline)
            Button("Open Tab") {
                _ = sessionManager.startSession(for: wt, setupCommands: wt.setupCommands)
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deadSessionPlaceholder(for wt: Worktree, sessionId: UUID) -> some View {
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
            HStack {
                Button("Restart") {
                    sessionManager.terminate(sessionId: sessionId)
                    _ = sessionManager.startSession(for: wt, setupCommands: wt.setupCommands)
                }
                .keyboardShortcut(.defaultAction)
                Button("Close Tab") {
                    sessionManager.terminate(sessionId: sessionId)
                }
            }
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
