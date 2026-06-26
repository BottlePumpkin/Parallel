import XCTest
import SwiftTerm
@testable import Parallel

/// Integration test: drive a real SwiftTerm `Terminal` (not a pure policy) the
/// same way our scroll forwarding does, and assert the actual wire bytes sent to
/// the program. This closes the gap between "the policy returns 64/65" and "the
/// program receives the correct SGR wheel report", through real SwiftTerm.
final class TerminalWheelEncodingTests: XCTestCase {

    /// Captures everything the terminal would write to the program (the PTY).
    private final class CaptureDelegate: TerminalDelegate {
        var sent: [UInt8] = []
        func send(source: Terminal, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
    }

    /// A terminal in SGR (1006) + any-event (1003) mouse mode, like Claude Code.
    private func mouseTrackingTerminal() -> (Terminal, CaptureDelegate) {
        let delegate = CaptureDelegate()
        let terminal = Terminal(delegate: delegate)
        terminal.feed(text: "\u{1b}[?1006h\u{1b}[?1003h")
        delegate.sent.removeAll() // ignore any handshake responses
        return (terminal, delegate)
    }

    func test_wheelUp_emitsSGRButton64() {
        let (terminal, delegate) = mouseTrackingTerminal()
        terminal.sendEvent(
            buttonFlags: TerminalMouseScroll.wheelButtonFlags(scrollingUp: true), x: 5, y: 3)
        XCTAssertEqual(String(decoding: delegate.sent, as: UTF8.self), "\u{1b}[<64;6;4M")
    }

    func test_wheelDown_emitsSGRButton65() {
        let (terminal, delegate) = mouseTrackingTerminal()
        terminal.sendEvent(
            buttonFlags: TerminalMouseScroll.wheelButtonFlags(scrollingUp: false), x: 5, y: 3)
        XCTAssertEqual(String(decoding: delegate.sent, as: UTF8.self), "\u{1b}[<65;6;4M")
    }
}
