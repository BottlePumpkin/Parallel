import SwiftUI

struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var selectedWorktreeId: UUID?
    @State private var showAddRepo = false
    @State private var showNewWorktree = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedWorktreeId)
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
        .sheet(isPresented: $showNewWorktree) { NewWorktreeSheet() }
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
}
