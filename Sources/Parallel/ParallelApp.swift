import SwiftUI

@main
struct ParallelApp: App {
    @State private var store: WorkspaceStore = {
        let s = WorkspaceStore(directory: WorkspaceStore.defaultDirectory)
        try? s.load()
        return s
    }()
    @State private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup("Parallel") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(store)
                .environment(sessionManager)
        }
        .windowResizability(.contentSize)
    }
}
