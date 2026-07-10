import Foundation

/// Leading-edge debounce gate for terminal bells (issue #12). Fires on the first
/// bell, then suppresses until `cooldown` seconds pass, collapsing a burst into a
/// single notification. Pure and value-typed; the caller injects a monotonic
/// timestamp (`ProcessInfo.processInfo.systemUptime`).
struct BellDebouncer {
    let cooldown: TimeInterval
    private var lastFire: TimeInterval?

    init(cooldown: TimeInterval = 2.0) {
        self.cooldown = cooldown
    }

    /// Returns true if this bell should raise a notification.
    mutating func shouldFire(now: TimeInterval) -> Bool {
        if let last = lastFire, now - last < cooldown { return false }
        lastFire = now
        return true
    }
}
