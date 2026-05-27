import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var selection: UUID?
    let onDelete: (UUID) -> Void
    let onAddWorktree: (UUID) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(store.repos) { repo in
                Section {
                    let items = store.worktrees.filter { $0.repoId == repo.id }
                    if items.isEmpty {
                        Text("(no worktrees)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(items) { wt in
                            WorktreeRow(worktree: wt)
                                .tag(wt.id as UUID?)
                                .contextMenu {
                                    Button("Delete Worktree…", role: .destructive) {
                                        onDelete(wt.id)
                                    }
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text(repo.displayName)
                        Spacer()
                        Button {
                            onAddWorktree(repo.id)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .help("New worktree in \(repo.displayName)")
                    }
                }
            }
            if store.repos.isEmpty {
                Text("(no repositories)")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct WorktreeRow: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    let worktree: Worktree

    var body: some View {
        let status = store.statuses[worktree.id]
        let session = sessionManager.session(for: worktree.id)

        HStack(spacing: 6) {
            stateDot(status: status, session: session)
            Text(worktree.displayName)
                .lineLimit(1)
            Spacer()
            if let s = status, s.lastError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(s.lastError ?? "")
            } else if let s = status, s.changedFiles > 0 {
                Text("\(s.changedFiles)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(.tertiary))
            }
        }
    }

    @ViewBuilder
    private func stateDot(status: WorktreeStatus?, session: SessionManager.SessionEntry?) -> some View {
        let sessionDead: Bool = {
            guard let s = session else { return true }
            if case .exited = s.session.state { return true }
            return false
        }()
        if sessionDead {
            Image(systemName: "moon.zzz.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if status?.isDirty == true {
            Circle().fill(.orange).frame(width: 8, height: 8)
        } else {
            Circle().fill(.green).frame(width: 8, height: 8)
        }
    }
}
