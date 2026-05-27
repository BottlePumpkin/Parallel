import SwiftUI

@main
struct ParallelApp: App {
    init() {
        AppLogger.bootstrapFileLogging()
    }

    @State private var store: WorkspaceStore = {
        let s = WorkspaceStore(directory: WorkspaceStore.defaultDirectory)
        try? s.load()
        return s
    }()
    @State private var sessionManager = SessionManager()
    @State private var statusWatcher: StatusWatcher?

    var body: some Scene {
        WindowGroup("Parallel") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(store)
                .environment(sessionManager)
                .onAppear {
                    if statusWatcher == nil {
                        let w = StatusWatcher(store: store)
                        statusWatcher = w
                        w.start()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    for wt in store.worktrees {
                        sessionManager.terminate(worktreeId: wt.id)
                    }
                    AppLogger.app.info("app terminating, sessions cleaned up")
                }
        }
        .windowResizability(.contentSize)
        .commands {
            ParallelCommands()
        }
    }
}
