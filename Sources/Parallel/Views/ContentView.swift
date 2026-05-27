import SwiftUI

struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var selectedWorktreeId: UUID?
    @State private var showAddRepo = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedWorktreeId)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            TerminalPaneView(worktreeId: selectedWorktreeId)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showAddRepo = true
                } label: {
                    Label("Add Repository", systemImage: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showAddRepo) {
            AddRepoSheet()
        }
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
