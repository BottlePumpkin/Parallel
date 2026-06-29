import XCTest
import SwiftTerm
@testable import Parallel

/// Pure-policy tests for suppressing bare hover motion.
///
/// Evidence: with Claude (any-event mouse mode) running, SwiftTerm forwards
/// every no-button mouse move as a *button-0* (left-drag) report — `ESC[<32;…`.
/// Claude reads that as "dragging" and highlights the block under the pointer,
/// while iTerm (which doesn't send drag-shaped hover) stays clean. We suppress
/// that hover stream; these tests pin exactly when.
final class TerminalMouseMotionTests: XCTestCase {

    func test_suppresses_whenAnyEventReportingAndNoModifier() {
        XCTAssertTrue(TerminalMouseMotion.shouldSuppressHover(
            mouseReportingEnabled: true, mouseMode: .anyEvent, commandActive: false))
    }

    func test_doesNotSuppress_whenReportingDisabled() {
        XCTAssertFalse(TerminalMouseMotion.shouldSuppressHover(
            mouseReportingEnabled: false, mouseMode: .anyEvent, commandActive: false))
    }

    func test_doesNotSuppress_whenMouseModeOff() {
        XCTAssertFalse(TerminalMouseMotion.shouldSuppressHover(
            mouseReportingEnabled: true, mouseMode: .off, commandActive: false))
    }

    // vt200 / buttonEventTracking don't report bare hover motion, so there is
    // nothing to suppress — leave them alone.
    func test_doesNotSuppress_whenButtonEventTracking() {
        XCTAssertFalse(TerminalMouseMotion.shouldSuppressHover(
            mouseReportingEnabled: true, mouseMode: .buttonEventTracking, commandActive: false))
    }

    // Command-hover drives link preview/highlight; keep it working.
    func test_doesNotSuppress_whenCommandHeld() {
        XCTAssertFalse(TerminalMouseMotion.shouldSuppressHover(
            mouseReportingEnabled: true, mouseMode: .anyEvent, commandActive: true))
    }
}
