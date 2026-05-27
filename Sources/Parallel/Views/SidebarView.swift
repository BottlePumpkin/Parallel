import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(store.repos) { repo in
                Section(repo.displayName) {
                    let items = store.worktrees.filter { $0.repoId == repo.id }
                    if items.isEmpty {
                        Text("(no worktrees)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(items) { wt in
                            WorktreeRow(worktree: wt)
                                .tag(wt.id as UUID?)
                        }
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
    let worktree: Worktree

    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 6, height: 6).foregroundStyle(.tertiary)
            Text(worktree.displayName)
                .lineLimit(1)
            Spacer()
        }
    }
}
