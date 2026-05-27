import SwiftUI

private struct SheetRepoId: Identifiable { let id: UUID }

struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @State private var selectedWorktreeId: UUID?
    @State private var showAddRepo = false
    @State private var showNewWorktree = false
    @State private var newWorktreeInitialRepoId: UUID?
    @State private var importWorktreesRepoId: UUID?
    @State private var pendingDeleteId: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selectedWorktreeId,
                onDelete: { id in pendingDeleteId = id },
                onAddWorktree: { repoId in
                    newWorktreeInitialRepoId = repoId
                    showNewWorktree = true
                },
                onImportWorktrees: { repoId in
                    importWorktreesRepoId = repoId
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            TerminalPaneView(worktreeId: selectedWorktreeId)
        }
        .toolbar {
            ToolbarItem {
                Button { showAddRepo = true } label: {
                    Label("Add Repository", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem {
                Button { showNewWorktree = true } label: {
                    Label("New Worktree", systemImage: "plus.square.on.square")
                }
                .disabled(store.repos.isEmpty)
            }
        }
        .sheet(isPresented: $showAddRepo) { AddRepoSheet() }
        .sheet(isPresented: $showNewWorktree, onDismiss: {
            newWorktreeInitialRepoId = nil
        }) {
            NewWorktreeSheet(initialRepoId: newWorktreeInitialRepoId)
        }
        .sheet(item: Binding(
            get: { importWorktreesRepoId.map(SheetRepoId.init) },
            set: { importWorktreesRepoId = $0?.id }
        )) { wrapper in
            ImportWorktreesSheet(repoId: wrapper.id)
        }
        .alert("Delete worktree?", isPresented: Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let id = pendingDeleteId, let wt = store.worktree(id: id) {
                Text("This will remove the worktree at \(wt.path.lastPathComponent). The branch is preserved.")
            }
        }
        .focusedValue(\.contentActions, ContentActions(
            newWorktree: { showNewWorktree = true },
            addRepo:     { showAddRepo = true },
            selectIndex: { idx in
                if idx < store.worktrees.count {
                    selectedWorktreeId = store.worktrees[idx].id
                }
            },
            closeCurrentSession: {
                if let id = selectedWorktreeId {
                    sessionManager.terminate(worktreeId: id)
                }
            },
            deleteCurrentWorktree: {
                pendingDeleteId = selectedWorktreeId
            }
        ))
        .onAppear {
            if selectedWorktreeId == nil {
                selectedWorktreeId = store.lastSelectedWorktreeId
            }
        }
        .onChange(of: selectedWorktreeId) { _, new in
            store.lastSelectedWorktreeId = new
            try? store.save()
        }
    }

    private func confirmDelete() {
        guard let id = pendingDeleteId, let wt = store.worktree(id: id),
              let repo = store.repos.first(where: { $0.id == wt.repoId }) else {
            pendingDeleteId = nil
            return
        }
        sessionManager.terminate(worktreeId: id)
        do {
            try WorktreeService().remove(repoRoot: repo.root, path: wt.path, force: false)
            store.removeWorktree(id: id)
        } catch {
            // Fallback: force remove (e.g., uncommitted changes blocked the normal path)
            try? WorktreeService().remove(repoRoot: repo.root, path: wt.path, force: true)
            store.removeWorktree(id: id)
        }
        pendingDeleteId = nil
    }
}
