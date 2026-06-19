import SwiftUI

/// Hidden, accessibility-visible element that surfaces SessionManager state to
/// XCUITest. Mounted only when `PARALLEL_E2E=1`. Reads as `staticTexts` whose
/// `.value` is the current count / active worktree id.
struct E2EProbeView: View {
    @Environment(SessionManager.self) private var sessionManager
    let selectedWorktreeId: UUID?

    var body: some View {
        let count = sessionManager.allRunningSessions.count
        VStack(spacing: 0) {
            Text("rsc")
                .accessibilityIdentifier("e2e.runningSessionCount")
                .accessibilityValue("\(count)")
            Text("awt")
                .accessibilityIdentifier("e2e.activeWorktreeId")
                .accessibilityValue(selectedWorktreeId?.uuidString ?? "")
        }
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .allowsHitTesting(false)
    }
}
