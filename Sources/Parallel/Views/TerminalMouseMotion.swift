import SwiftTerm

/// Pure policy for suppressing bare hover motion reports.
///
/// Under any-event mouse tracking SwiftTerm forwards every no-button mouse move
/// as a button-0 (left-drag) report. A TUI reads that as dragging — Claude Code
/// highlights the block under the pointer on a mere hover, which iTerm never
/// does. `ParallelTerminalView` consults this policy to drop that hover stream
/// while leaving wheel reports, clicks, real drags, and Cmd-hover link preview
/// intact. Kept pure so the decision is unit-tested without an AppKit window.
enum TerminalMouseMotion {

    static func shouldSuppressHover(mouseReportingEnabled: Bool,
                                    mouseMode: Terminal.MouseMode,
                                    commandActive: Bool) -> Bool {
        // `sendMotionEvent()` is true only for any-event tracking — the one mode
        // that emits bare hover motion. Other modes have nothing to suppress.
        mouseReportingEnabled && !commandActive && mouseMode.sendMotionEvent()
    }
}
