import Foundation

/// Coalesces PTY read chunks so the main thread feeds the terminal once per
/// scheduling cycle instead of once per chunk.
///
/// Why: the PTY read pump runs on a background queue and fires rapidly under
/// high throughput (e.g. an iOS build dumping megabytes of build log). Doing a
/// `DispatchQueue.main.async { view.feed(chunk) }` per chunk floods the main
/// queue with thousands of tiny blocks — the producer outruns the main
/// thread's ability to parse + render, the backlog grows unbounded, and the
/// app beachballs. Accumulating bytes here and signalling the caller to
/// schedule at most ONE main-thread drain collapses N hops into 1 and lets the
/// terminal parser consume bytes in bulk.
///
/// Thread-safe: `append` is called from the background read pump, `drain` from
/// the main thread. A lock guards the small critical sections.
final class PTYOutputCoalescer {
    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var flushScheduled = false

    /// Append bytes from the background read pump.
    /// - Returns: `true` if the caller should schedule a main-thread flush
    ///   (i.e. no flush is already pending); `false` if one is already queued.
    func append(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pending.append(contentsOf: data)
        if flushScheduled { return false }
        flushScheduled = true
        return true
    }

    /// Drain all bytes accumulated since the last drain and clear the
    /// scheduled flag so the next `append` re-schedules. Call on the main
    /// thread inside the scheduled flush.
    func drain() -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        let out = pending
        pending.removeAll(keepingCapacity: true)
        flushScheduled = false
        return out
    }
}
