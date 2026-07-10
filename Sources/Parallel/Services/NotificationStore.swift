import Foundation
import Observation

/// In-memory notification history (issue #12). Cleared on restart (no disk
/// persistence in v1). Newest first; bounded to `cap` entries.
@Observable
@MainActor
final class NotificationStore {
    private(set) var items: [AppNotification] = []
    /// Set by a list-row tap or a banner click; ContentView observes and clears it.
    var navigationTarget: NavigationTarget?
    private let cap: Int

    init(cap: Int = 200) { self.cap = cap }

    var unreadCount: Int { items.lazy.filter { !$0.isRead }.count }

    func add(_ notification: AppNotification) {
        items.insert(notification, at: 0)
        if items.count > cap { items.removeLast(items.count - cap) }
    }

    func markAllRead() {
        for i in items.indices where !items[i].isRead { items[i].isRead = true }
    }

    func clearAll() { items.removeAll() }
}
