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
    /// Outcome of a single `drain`. `hasMore` is true when the per-feed cap
    /// left bytes behind, signalling the caller to schedule another flush so
    /// the remainder is fed without one frame doing all the work.
    struct DrainResult: Equatable {
        let bytes: [UInt8]
        let hasMore: Bool
    }

    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var flushScheduled = false

    /// Append bytes from the background read pump.
    /// - Returns: `true` if the caller should schedule a main-thread flush
    ///   (i.e. no flush is already pending); `false` if one is already queued
    ///   (including while a capped drain chain is still in flight).
    func append(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pending.append(contentsOf: data)
        if flushScheduled { return false }
        flushScheduled = true
        return true
    }

    /// Drain up to `max` bytes accumulated since the last drain. If bytes
    /// remain, the scheduled flag stays set and `hasMore` is true so the
    /// caller keeps draining; otherwise the flag clears so the next `append`
    /// re-schedules. Call on the main thread inside the scheduled flush.
    func drain(max: Int) -> DrainResult {
        lock.lock()
        defer { lock.unlock() }
        let n = Swift.min(Swift.max(max, 0), pending.count)
        let out = Array(pending[0..<n])
        pending.removeFirst(n)
        let more = !pending.isEmpty
        flushScheduled = more
        return DrainResult(bytes: out, hasMore: more)
    }
}
