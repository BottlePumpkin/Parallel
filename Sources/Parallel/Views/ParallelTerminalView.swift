import AppKit
import SwiftTerm

/// SwiftTerm `TerminalView` with the gaps a full-screen TUI exposes filled in.
///
/// SwiftTerm's `scrollWheel` always scrolls its own buffer and never reports the
/// wheel to a program that turned on mouse tracking. Under the alternate screen
/// (Claude Code, vim, less, …) that buffer is empty, so the wheel does nothing —
/// while iTerm2/Terminal.app forward it and the program scrolls.
///
/// SwiftTerm seals `scrollWheel` (`public override`, not `open`), so we can't
/// re-override it from this module. Instead we intercept scroll events with a
/// local event monitor: when the pointer is over the visible terminal and the
/// program has mouse reporting on, we forward the wheel as SGR mouse-button
/// reports and consume the event; otherwise we pass it through to SwiftTerm's
/// native scrollback. Every decision defers to the unit-tested
/// `TerminalMouseScroll` policy; this layer is thin AppKit glue.
final class ParallelTerminalView: TerminalView {

    private var eventMonitors: [Any] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitorsIfNeeded()
        } else {
            removeMonitors()
        }
    }

    deinit { removeMonitors() }

    private func installMonitorsIfNeeded() {
        guard eventMonitors.isEmpty else { return }
        // Forward the wheel to mouse-tracking programs (they own scrolling).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self else { return event }
            return self.forwardWheelIfNeeded(event) ? nil : event
        }) { eventMonitors.append(m) }
        // Drop bare hover motion that SwiftTerm mis-reports as a left-drag,
        // which a TUI (Claude) reacts to by highlighting the block on hover.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            guard let self else { return event }
            return self.suppressHoverMotion(event) ? nil : event
        }) { eventMonitors.append(m) }
    }

    private func removeMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
    }

    /// Returns true (consume) when this is the visible terminal under the pointer
    /// and the program's bare hover motion should be suppressed.
    private func suppressHoverMotion(_ event: NSEvent) -> Bool {
        guard !isHidden, let window, event.window === window else { return false }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
        return TerminalMouseMotion.shouldSuppressHover(
            mouseReportingEnabled: allowMouseReporting,
            mouseMode: getTerminal().mouseMode,
            commandActive: event.modifierFlags.contains(.command)
        )
    }

    /// Forward the wheel to the program if this is the visible terminal under the
    /// pointer and mouse reporting is on. Returns true when consumed.
    private func forwardWheelIfNeeded(_ event: NSEvent) -> Bool {
        guard !isHidden, let window, event.window === window else { return false }
        let pointInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pointInView) else { return false }

        let term = getTerminal()
        guard TerminalMouseScroll.shouldForwardToApp(
            mouseReportingEnabled: allowMouseReporting,
            mouseMode: term.mouseMode
        ) else { return false }

        let ticks = TerminalMouseScroll.tickCount(forDeltaY: Double(event.deltaY))
        guard ticks > 0 else { return true } // mouse-mode owns the wheel; swallow no-op
        let flags = TerminalMouseScroll.wheelButtonFlags(scrollingUp: event.deltaY > 0)
        let pos = wheelGridPosition(at: pointInView, cols: term.cols, rows: term.rows)
        for _ in 0..<ticks {
            term.sendEvent(buttonFlags: flags, x: pos.col, y: pos.row)
        }
        return true
    }

    /// Mouse cell under the pointer for the wheel report. `calculateMouseHit` is
    /// internal to SwiftTerm, so derive col/row from the point and the public
    /// grid size — exact position is not critical for wheel reports.
    private func wheelGridPosition(at point: CGPoint, cols: Int, rows: Int) -> (col: Int, row: Int) {
        guard bounds.width > 0, bounds.height > 0, cols > 0, rows > 0 else { return (0, 0) }
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        let col = min(max(0, Int(point.x / cellW)), cols - 1)
        let row = min(max(0, Int((bounds.height - point.y) / cellH)), rows - 1)
        return (col, row)
    }
}
