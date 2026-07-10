import XCTest
@testable import Parallel

/// Issue #12: in-memory notification history. Newest first, unread badge count,
/// mark-all-read on popover open, clear-all, and a bounded cap.
@MainActor
final class NotificationStoreTests: XCTestCase {
    private func note(_ name: String) -> AppNotification {
        AppNotification(kind: .needsAttention, worktreeId: UUID(), sessionId: UUID(),
                        worktreeName: name, branch: "main", tabLabel: "shell 1")
    }

    func test_addPrependsNewestFirst_andCountsUnread() {
        let s = NotificationStore()
        s.add(note("a"))
        s.add(note("b"))
        XCTAssertEqual(s.items.map(\.worktreeName), ["b", "a"])
        XCTAssertEqual(s.unreadCount, 2)
    }

    func test_markAllReadZeroesUnread() {
        let s = NotificationStore()
        s.add(note("a")); s.add(note("b"))
        s.markAllRead()
        XCTAssertEqual(s.unreadCount, 0)
        XCTAssertEqual(s.items.count, 2)
    }

    func test_clearAllEmpties() {
        let s = NotificationStore()
        s.add(note("a"))
        s.clearAll()
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertEqual(s.unreadCount, 0)
    }

    func test_capDropsOldest() {
        let s = NotificationStore(cap: 2)
        s.add(note("a")); s.add(note("b")); s.add(note("c"))
        XCTAssertEqual(s.items.map(\.worktreeName), ["c", "b"])
    }

    func test_addedAsReadDoesNotCountUnread() {
        let s = NotificationStore()
        var n = note("a"); n.isRead = true
        s.add(n)
        XCTAssertEqual(s.unreadCount, 0)
    }

    func test_isReadFlagMatchesBannerPolicy() {
        // postNotification sets isRead = appActive && sessionVisible; the store must
        // honour a pre-read entry (no unread badge for something you're looking at).
        let s = NotificationStore()
        var read = note("a"); read.isRead = true
        s.add(read)
        s.add(note("b"))
        XCTAssertEqual(s.unreadCount, 1)
    }
}
