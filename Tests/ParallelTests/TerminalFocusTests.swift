import XCTest
@testable import Parallel

final class TerminalFocusTests: XCTestCase {

    // MARK: - shouldTakeFocus (auto-focus on worktree/tab switch — issue #7)
    //
    // A terminal grabs keyboard focus only when a previously-hidden view
    // becomes visible. It must NOT steal focus when it was already visible,
    // when it is being hidden, or while it stays hidden.

    func test_shouldTakeFocus_whenBecomingVisible() {
        XCTAssertTrue(MountedTerminalView.shouldTakeFocus(wasHidden: true, isVisible: true))
    }

    func test_shouldTakeFocus_notWhenAlreadyVisible() {
        XCTAssertFalse(MountedTerminalView.shouldTakeFocus(wasHidden: false, isVisible: true))
    }

    func test_shouldTakeFocus_notWhenBecomingHidden() {
        XCTAssertFalse(MountedTerminalView.shouldTakeFocus(wasHidden: true, isVisible: false))
    }

    func test_shouldTakeFocus_notWhenStayingHidden() {
        XCTAssertFalse(MountedTerminalView.shouldTakeFocus(wasHidden: false, isVisible: false))
    }
}
