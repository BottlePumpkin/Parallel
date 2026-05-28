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
    @State private var renameTargetId: UUID?
    @State private var renameText: String = ""

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
                },
                onRename: { id in
                    renameText = store.worktree(id: id)?.displayName ?? ""
                    renameTargetId = id
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
        .sheet(item: Binding(
            get: { pendingDeleteId.flatMap { store.worktree(id: $0) } },
            set: { if $0 == nil { pendingDeleteId = nil } }
        )) { wt in
            DeleteWorktreeSheet(worktree: wt) { alsoDeleteBranch in
                confirmDelete(alsoDeleteBranch: alsoDeleteBranch)
            }
        }
        .alert("Rename worktree", isPresented: Binding(
            get: { renameTargetId != nil },
            set: { if !$0 { renameTargetId = nil } }
        )) {
            TextField("Display name", text: $renameText)
            Button("Save") { confirmRename() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let id = renameTargetId, let wt = store.worktree(id: id) {
                Text("Branch: \(wt.branch)")
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

    private func confirmRename() {
        guard let id = renameTargetId else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { renameTargetId = nil; return }
        if let idx = store.worktrees.firstIndex(where: { $0.id == id }) {
            store.worktrees[idx].displayName = trimmed
            try? store.save()
        }
        renameTargetId = nil
    }

    private func confirmDelete(alsoDeleteBranch: Bool) {
        guard let id = pendingDeleteId, let wt = store.worktree(id: id),
              let repo = store.repos.first(where: { $0.id == wt.repoId }) else {
            pendingDeleteId = nil
            return
        }
        sessionManager.terminate(worktreeId: id)
        let svc = WorktreeService()
        do {
            try svc.remove(repoRoot: repo.root, path: wt.path, force: false)
        } catch {
            // Fallback: force remove (e.g., uncommitted changes blocked the normal path)
            try? svc.remove(repoRoot: repo.root, path: wt.path, force: true)
        }
        if alsoDeleteBranch {
            try? svc.deleteBranch(repoRoot: repo.root, branch: wt.branch)
        }
        store.removeWorktree(id: id)
        pendingDeleteId = nil
    }
}
