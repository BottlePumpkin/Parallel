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

    // MARK: - shouldRefreshProgram (force SIGWINCH repaint on switch — issue #24)
    //
    // A becoming-visible terminal re-emits its grid size to the PTY so a
    // full-screen TUI (Claude Code) repaints. needsDisplay alone leaves the
    // alt-screen blank after a worktree/tab switch; only a SIGWINCH fixes it.
    // The trigger must match focus: a hidden→visible transition ONLY — never
    // while staying visible, becoming hidden, or staying hidden (which would
    // spam redundant SIGWINCHes).

    func test_shouldRefreshProgram_whenBecomingVisible() {
        XCTAssertTrue(MountedTerminalView.shouldRefreshProgram(wasHidden: true, isVisible: true))
    }

    func test_shouldRefreshProgram_notWhenAlreadyVisible() {
        XCTAssertFalse(MountedTerminalView.shouldRefreshProgram(wasHidden: false, isVisible: true))
    }

    func test_shouldRefreshProgram_notWhenBecomingHidden() {
        XCTAssertFalse(MountedTerminalView.shouldRefreshProgram(wasHidden: true, isVisible: false))
    }

    func test_shouldRefreshProgram_notWhenStayingHidden() {
        XCTAssertFalse(MountedTerminalView.shouldRefreshProgram(wasHidden: false, isVisible: false))
    }
}
