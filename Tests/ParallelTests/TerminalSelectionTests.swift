import XCTest
import SwiftTerm
@testable import Parallel

/// Pure-policy tests for drag-to-select (issue #21).
///
/// While a program has mouse reporting on, SwiftTerm forwards drags to it, so
/// native text selection (and ⌘C) is impossible. iTerm2 lets a plain drag
/// select anyway. We match that: when a left-drag begins we temporarily turn
/// `allowMouseReporting` off so SwiftTerm selects natively, while single clicks
/// and the wheel still reach the program. This policy decides when a drag
/// should bypass reporting.
final class TerminalSelectionTests: XCTestCase {

    func test_bypasses_whenReportingActive_anyEvent() {
        XCTAssertTrue(TerminalSelectionBypass.shouldBypassReporting(
            mouseReportingEnabled: true, mouseMode: .anyEvent))
    }

    func test_bypasses_whenReportingActive_buttonTracking() {
        XCTAssertTrue(TerminalSelectionBypass.shouldBypassReporting(
            mouseReportingEnabled: true, mouseMode: .buttonEventTracking))
    }

    // No reporting in effect → native selection already works; nothing to bypass.
    func test_doesNotBypass_whenMouseModeOff() {
        XCTAssertFalse(TerminalSelectionBypass.shouldBypassReporting(
            mouseReportingEnabled: true, mouseMode: .off))
    }

    func test_doesNotBypass_whenReportingDisabled() {
        XCTAssertFalse(TerminalSelectionBypass.shouldBypassReporting(
            mouseReportingEnabled: false, mouseMode: .anyEvent))
    }
}
