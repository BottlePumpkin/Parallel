import XCTest
import SwiftTerm
@testable import Parallel

/// Pins the SwiftTerm contract issue #12 relies on: feeding a raw BEL (0x07) to a
/// TerminalView must reach `SessionTerminalDelegate.bell(source:)` and fire its
/// `onBell`. The e2e cannot reliably reach this SwiftTerm-internal path, so this
/// unit test is the load-bearing coverage of the bell → notification linkage.
final class BellRoutingTests: XCTestCase {
    @MainActor
    func test_feedingBEL_firesOnBell() throws {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/zsh", cwd: tmp) else {
            return XCTFail("could not fork PTY")
        }
        defer { pty.terminate() }

        let view = ParallelTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let delegate = SessionTerminalDelegate(pty: pty)
        var fired = false
        delegate.onBell = { fired = true }
        view.terminalDelegate = delegate

        view.feed(byteArray: ArraySlice([0x07]))

        XCTAssertTrue(fired, "feeding BEL should reach SessionTerminalDelegate.onBell")
    }

    /// Full SessionManager path: a bell on a NON-visible session adds one unread
    /// notification to the store (mirrors the e2e scenario, run locally).
    @MainActor
    func test_backgroundBell_addsUnreadNotification() throws {
        let sm = SessionManager()
        let store = NotificationStore()
        sm.notificationStore = store

        let tmp = FileManager.default.temporaryDirectory
        let wt = Worktree(repoId: UUID(), path: tmp, branch: "alpha", displayName: "alpha")
        guard let entry = sm.startSession(for: wt, setupCommands: []) else {
            return XCTFail("startSession failed")
        }
        sm.visibleWorktreeId = nil   // nothing visible → session is "background"

        entry.terminalView.feed(byteArray: ArraySlice([0x07]))

        // onBell hops through DispatchQueue.main.async → handleBell; pump the queue.
        let exp = expectation(description: "notification added")
        DispatchQueue.main.async { DispatchQueue.main.async { exp.fulfill() } }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(store.items.count, 1, "a background bell should add one notification")
        XCTAssertEqual(store.unreadCount, 1, "the notification should be unread")
    }
}
