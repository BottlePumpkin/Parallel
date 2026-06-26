import XCTest
import SwiftTerm
@testable import Parallel

/// Contract tests pinning the SwiftTerm behavior our terminal policies depend
/// on. These are characterization tests: they pass against the pinned SwiftTerm
/// (1.13.0) on purpose. If a future SwiftTerm bump changes any of these, the
/// build goes red here — a signal to re-check TerminalMouseScroll /
/// TerminalMouseMotion / TerminalSelectionBypass, which all assume them.
///
/// Why this matters: the whole "terminal quality regression" was SwiftTerm's
/// defaults reacting to Claude turning on mouse tracking, not our code. A silent
/// dependency change is exactly what we want to catch early.
final class SwiftTermContractTests: XCTestCase {

    // Our scroll/hover policies assume reporting is ON by default (we only ever
    // turn it off transiently for a drag). If SwiftTerm flips this default, a
    // plain terminal would stop forwarding the wheel and our logic breaks.
    @MainActor
    func test_terminalView_mouseReporting_defaultsOn() {
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertTrue(view.allowMouseReporting,
                      "SwiftTerm default changed — re-check the terminal mouse policies")
    }

    // TerminalMouseMotion.shouldSuppressHover and TerminalMouseScroll both rely
    // on "any-event is the only mode that reports bare motion". Pin that.
    func test_mouseMode_anyEvent_isTheOnlyMotionReportingMode() {
        XCTAssertTrue(Terminal.MouseMode.anyEvent.sendMotionEvent())
        XCTAssertFalse(Terminal.MouseMode.buttonEventTracking.sendMotionEvent())
        XCTAssertFalse(Terminal.MouseMode.vt200.sendMotionEvent())
        XCTAssertFalse(Terminal.MouseMode.off.sendMotionEvent())
    }

    // Our policies treat "mouse reporting active" as `mouseMode != .off`. Pin the
    // distinct cases so a renamed/removed case fails here rather than silently.
    func test_mouseMode_offIsDistinctFromTrackingModes() {
        XCTAssertNotEqual(Terminal.MouseMode.off, .anyEvent)
        XCTAssertNotEqual(Terminal.MouseMode.off, .buttonEventTracking)
        XCTAssertNotEqual(Terminal.MouseMode.off, .vt200)
    }
}
