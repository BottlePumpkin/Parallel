import XCTest
@testable import Parallel

/// Tests for the opt-in terminal I/O debug logger's extraction step.
///
/// Privacy by construction: the logger only ever emits a string for an SGR
/// mouse/control report (`ESC [ < … `, just coordinates). For anything else —
/// keystrokes, pasted content, arrow keys — extraction returns nil, so typed or
/// pasted text can never be logged even when the facility is enabled.
final class TerminalIODebugTests: XCTestCase {

    func test_describes_sgrMouseReport() {
        let bytes = Array("\u{1b}[<32;10;5m".utf8)
        XCTAssertEqual(TerminalIODebug.controlReportDescription(from: bytes),
                       "ESC[<32;10;5m")
    }

    func test_nil_forKeystrokes() {
        XCTAssertNil(TerminalIODebug.controlReportDescription(from: Array("ls -la\n".utf8)))
    }

    func test_nil_forArrowKeyEscape() {
        XCTAssertNil(TerminalIODebug.controlReportDescription(from: Array("\u{1b}[A".utf8)))
    }

    // Pasted content must never be logged (it can contain secrets).
    func test_nil_forBracketedPasteContent() {
        let paste = Array("\u{1b}[200~hunter2\u{1b}[201~".utf8)
        XCTAssertNil(TerminalIODebug.controlReportDescription(from: paste))
    }

    func test_nil_forEmpty() {
        XCTAssertNil(TerminalIODebug.controlReportDescription(from: []))
    }
}
