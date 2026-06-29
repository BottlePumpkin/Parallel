import SwiftTerm

/// Pure policy for forwarding the scroll wheel to a mouse-tracking program.
///
/// When a full-screen TUI (e.g. Claude Code) enables mouse reporting it owns
/// scrolling itself and expects the terminal to deliver wheel turns as SGR
/// mouse-button reports. SwiftTerm's `scrollWheel` ignores `mouseMode` and only
/// scrolls its own buffer — empty under the alternate screen — so the program
/// never receives the wheel and never scrolls. `ParallelTerminalView` consults
/// this policy to bridge the gap (matching iTerm2). Kept pure so the decision
/// and encoding are unit-tested without an AppKit window.
enum TerminalMouseScroll {

    /// Forward the wheel to the program instead of scrolling our own buffer
    /// only while the program has mouse reporting turned on.
    static func shouldForwardToApp(mouseReportingEnabled: Bool,
                                   mouseMode: Terminal.MouseMode) -> Bool {
        mouseReportingEnabled && mouseMode != .off
    }

    /// xterm Cb button code for a wheel turn: 64 = up, 65 = down.
    static func wheelButtonFlags(scrollingUp: Bool) -> Int {
        scrollingUp ? 64 : 65
    }

    /// How many discrete wheel reports to emit for a scroll delta. Clamped so a
    /// single fast flick can't flood the program, and a tiny delta still moves.
    static func tickCount(forDeltaY deltaY: Double) -> Int {
        let magnitude = abs(deltaY)
        if magnitude == 0 { return 0 }
        return min(10, max(1, Int(magnitude.rounded())))
    }
}
