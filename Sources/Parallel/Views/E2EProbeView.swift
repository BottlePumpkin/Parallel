import SwiftUI
import AppKit
import Combine
import SwiftTerm

/// Hidden, accessibility-visible element that surfaces SessionManager state to
/// XCUITest. Mounted only when `PARALLEL_E2E=1`. Reads as `staticTexts` whose
/// `.value` is the current count / active worktree id / terminal-focus flag.
struct E2EProbeView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(NotificationStore.self) private var notificationStore
    let selectedWorktreeId: UUID?

    /// Polled view of whether a terminal currently holds keyboard focus. Lets a
    /// UI test assert auto-focus (issue #7) by reading real first-responder
    /// state instead of typing into the pane — the latter can hang XCUITest
    /// indefinitely when nothing accepts the keystrokes.
    @State private var terminalHasFocus = false
    /// Mouse/control reports the active terminal forwarded (e2e mouse mode only).
    @State private var mouseReports = ""
    /// Whether the active terminal currently has a text selection.
    @State private var selectionActive = false
    private let focusPoll = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let count = sessionManager.allRunningSessions.count
        VStack(spacing: 0) {
            // Read-only probes: never intercept user input. `.allowsHitTesting(false)`
            // must sit on THIS subtree only — a parent's false disables the whole
            // branch and a child's true cannot re-enable it, which would make the
            // emitBell button below unclickable (issue #12).
            VStack(spacing: 0) {
                Text("rsc")
                    .accessibilityIdentifier("e2e.runningSessionCount")
                    .accessibilityValue("\(count)")
                Text("awt")
                    .accessibilityIdentifier("e2e.activeWorktreeId")
                    .accessibilityValue(selectedWorktreeId?.uuidString ?? "")
                Text("trf")
                    .accessibilityIdentifier("e2e.terminalHasFocus")
                    .accessibilityValue(terminalHasFocus ? "1" : "0")
                Text("fs")
                    .accessibilityIdentifier("e2e.terminalFontSize")
                    .accessibilityValue("\(Int(sessionManager.terminalFontSize))")
                Text("mr")
                    .accessibilityIdentifier("e2e.mouseReports")
                    .accessibilityValue(mouseReports)
                Text("sel")
                    .accessibilityIdentifier("e2e.selectionActive")
                    .accessibilityValue(selectionActive ? "1" : "0")
                Text("unread")
                    .accessibilityIdentifier("e2e.unreadNotificationCount")
                    .accessibilityValue("\(notificationStore.unreadCount)")
            }
            .allowsHitTesting(false)

            // Hittable e2e affordance — must NOT be under allowsHitTesting(false).
            Button("emitBell") { sessionManager.e2eEmitBellInBackground() }
                .accessibilityIdentifier("e2e.emitBackgroundBell")
        }
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .onReceive(focusPoll) { _ in
            terminalHasFocus = Self.aTerminalIsFirstResponder()
            mouseReports = E2ETerminalProbe.reports
            selectionActive = Self.activeSelectionActive(sessionManager, selectedWorktreeId)
        }
    }

    /// Whether the active worktree's terminal currently has a selection.
    private static func activeSelectionActive(_ sm: SessionManager, _ worktreeId: UUID?) -> Bool {
        guard let worktreeId, let entry = sm.activeSession(for: worktreeId) else { return false }
        return entry.terminalView.selectionActive
    }

    /// True when the key window's first responder is a SwiftTerm `TerminalView`
    /// (or a view nested inside one). Walking up the superview chain tolerates
    /// SwiftTerm parking focus on an internal subview.
    private static func aTerminalIsFirstResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is TerminalView { return true }
        var view = (responder as? NSView)?.superview
        while let current = view {
            if current is TerminalView { return true }
            view = current.superview
        }
        return false
    }
}
