import SwiftUI
import AppKit

@main
struct ParallelApp: App {
    init() {
        AppLogger.bootstrapFileLogging()
        // SwiftPM bare-executable launches don't set the activation policy,
        // which leaves the menu bar disabled and keyboard shortcuts unreachable.
        // Force regular foreground app so .commands { ParallelCommands() } works.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Notifications.requestPermission()
    }

    @State private var store: WorkspaceStore = {
        let s = WorkspaceStore(directory: WorkspaceStore.defaultDirectory)
        try? s.load()
        return s
    }()
    @State private var sessionManager = SessionManager()
    @State private var statusWatcher: StatusWatcher?
    @State private var caffeinate = CaffeinateManager()

    var body: some Scene {
        WindowGroup("Parallel") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(store)
                .environment(sessionManager)
                .environment(caffeinate)
                .onAppear {
                    if statusWatcher == nil {
                        let w = StatusWatcher(store: store)
                        statusWatcher = w
                        w.start()
                    }
                    sessionManager.store = store
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Detach from store first so the terminate cascade doesn't
                    // wipe persisted tab specs we want to restore next launch.
                    sessionManager.store = nil
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
