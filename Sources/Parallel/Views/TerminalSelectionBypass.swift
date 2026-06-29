import SwiftTerm

/// Pure policy for drag-to-select (issue #21).
///
/// While the program has mouse reporting on, SwiftTerm forwards drags to it and
/// native text selection is impossible. iTerm2 selects on a plain drag anyway;
/// we match that by turning `allowMouseReporting` off once a left-drag begins,
/// so SwiftTerm selects natively. Single clicks and the wheel still reach the
/// program. Kept pure so the decision is unit-tested without AppKit.
enum TerminalSelectionBypass {

    static func shouldBypassReporting(mouseReportingEnabled: Bool,
                                      mouseMode: Terminal.MouseMode) -> Bool {
        // Only meaningful while reporting would actually forward the drag; with
        // reporting off or mode off, native selection already works.
        mouseReportingEnabled && mouseMode != .off
    }
}
