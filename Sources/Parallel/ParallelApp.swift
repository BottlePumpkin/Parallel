import SwiftUI
import AppKit

/// Strips AppKit's standard ⌘W window-close after the menu bar is built so ⌘W
/// maps only to Worktree ▸ "Close Session" (issue #19).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI builds the menu bar during/after launch; defer a runloop tick
        // so the standard File ▸ Close item exists before we clear its ⌘W.
        DispatchQueue.main.async {
            AppMenuConfigurator.stripDefaultCloseShortcut(in: NSApp.mainMenu)
        }
    }
}

@main
struct ParallelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLogger.bootstrapFileLogging()
        // SwiftPM bare-executable launches don't set the activation policy,
        // which leaves the menu bar disabled and keyboard shortcuts unreachable.
        // Force regular foreground app so .commands { ParallelCommands() } works.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if !TestMode.isE2E() {
            Notifications.requestPermission()
        }
    }

    @State private var store: WorkspaceStore = {
        let dir = TestMode.supportDirectory() ?? WorkspaceStore.defaultDirectory
        let s = WorkspaceStore(directory: dir)
        try? s.load()
        TestSeed.applyIfNeeded(to: s)
        return s
    }()
    @State private var sessionManager = SessionManager()
    @State private var statusWatcher: StatusWatcher?
    @State private var caffeinate = CaffeinateManager()
    @State private var updateChecker = UpdateChecker()
    @State private var updater = Updater()

    var body: some Scene {
        WindowGroup("Parallel") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(store)
                .environment(sessionManager)
                .environment(caffeinate)
                .environment(updateChecker)
                .environment(updater)
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
