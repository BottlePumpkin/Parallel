import XCTest
import CoreGraphics
@testable import Parallel

final class TerminalFontTests: XCTestCase {

    // MARK: - clampedFontSize

    func test_clampedFontSize_within_range_unchanged() {
        XCTAssertEqual(SessionManager.clampedFontSize(13), 13)
    }

    func test_clampedFontSize_below_min_clamps_to_min() {
        XCTAssertEqual(SessionManager.clampedFontSize(2), SessionManager.minFontSize)
    }

    func test_clampedFontSize_above_max_clamps_to_max() {
        XCTAssertEqual(SessionManager.clampedFontSize(999), SessionManager.maxFontSize)
    }

    func test_clampedFontSize_at_bounds_unchanged() {
        XCTAssertEqual(SessionManager.clampedFontSize(SessionManager.minFontSize), SessionManager.minFontSize)
        XCTAssertEqual(SessionManager.clampedFontSize(SessionManager.maxFontSize), SessionManager.maxFontSize)
    }

    // MARK: - steppedFontSize (⌘+ / ⌘-)

    func test_steppedFontSize_increases_by_one_step() {
        XCTAssertEqual(
            SessionManager.steppedFontSize(from: 13, delta: SessionManager.fontSizeStep),
            13 + SessionManager.fontSizeStep
        )
    }

    func test_steppedFontSize_decreases_by_one_step() {
        XCTAssertEqual(
            SessionManager.steppedFontSize(from: 13, delta: -SessionManager.fontSizeStep),
            13 - SessionManager.fontSizeStep
        )
    }

    func test_steppedFontSize_does_not_exceed_max() {
        XCTAssertEqual(
            SessionManager.steppedFontSize(from: SessionManager.maxFontSize, delta: SessionManager.fontSizeStep),
            SessionManager.maxFontSize
        )
    }

    func test_steppedFontSize_does_not_drop_below_min() {
        XCTAssertEqual(
            SessionManager.steppedFontSize(from: SessionManager.minFontSize, delta: -SessionManager.fontSizeStep),
            SessionManager.minFontSize
        )
    }

    // MARK: - terminalFont resolves at the requested size

    func test_terminalFont_uses_requested_size() {
        XCTAssertEqual(SessionManager.terminalFont(size: 17).pointSize, 17)
    }

    func test_defaultFont_uses_default_size() {
        XCTAssertEqual(SessionManager.preferredTerminalFont.pointSize, SessionManager.defaultFontSize)
    }
}
