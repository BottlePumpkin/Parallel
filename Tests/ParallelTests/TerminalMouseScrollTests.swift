import XCTest
import SwiftTerm
@testable import Parallel

/// Pure-policy tests for forwarding the scroll wheel to a mouse-tracking app.
///
/// Context: full-screen TUIs (e.g. Claude Code) enable mouse reporting + the
/// alternate screen. Their own scroll consumes wheel events delivered as SGR
/// mouse-button reports (64 = up, 65 = down). iTerm forwards them; SwiftTerm's
/// `scrollWheel` ignores `mouseMode` and only scrolls its own (empty, in
/// alt-screen) buffer — so the app never scrolls. We bridge that gap, and these
/// tests pin the decision + encoding without needing an AppKit window.
final class TerminalMouseScrollTests: XCTestCase {

    // MARK: - shouldForwardToApp

    func test_forwards_whenReportingEnabledAndMouseModeActive() {
        XCTAssertTrue(TerminalMouseScroll.shouldForwardToApp(
            mouseReportingEnabled: true, mouseMode: .anyEvent))
    }

    func test_doesNotForward_whenMouseModeOff() {
        XCTAssertFalse(TerminalMouseScroll.shouldForwardToApp(
            mouseReportingEnabled: true, mouseMode: .off))
    }

    func test_doesNotForward_whenReportingDisabled() {
        XCTAssertFalse(TerminalMouseScroll.shouldForwardToApp(
            mouseReportingEnabled: false, mouseMode: .anyEvent))
    }

    // MARK: - wheelButtonFlags (xterm Cb codes)

    func test_wheelButtonFlags_up_is64() {
        XCTAssertEqual(TerminalMouseScroll.wheelButtonFlags(scrollingUp: true), 64)
    }

    func test_wheelButtonFlags_down_is65() {
        XCTAssertEqual(TerminalMouseScroll.wheelButtonFlags(scrollingUp: false), 65)
    }

    // MARK: - tickCount (how many wheel reports per scroll delta)

    func test_tickCount_zeroDelta_isZero() {
        XCTAssertEqual(TerminalMouseScroll.tickCount(forDeltaY: 0), 0)
    }

    func test_tickCount_smallDelta_isAtLeastOne() {
        XCTAssertEqual(TerminalMouseScroll.tickCount(forDeltaY: 0.2), 1)
    }

    func test_tickCount_isCapped() {
        XCTAssertEqual(TerminalMouseScroll.tickCount(forDeltaY: 999), 10)
    }

    func test_tickCount_usesMagnitude_forNegativeDelta() {
        XCTAssertEqual(TerminalMouseScroll.tickCount(forDeltaY: -3), 3)
    }
}
