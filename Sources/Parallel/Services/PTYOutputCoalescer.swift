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
/// Backpressure: when `pending` crosses the high watermark the `onPause`
/// handler is invoked to stop reading the PTY (so the child blocks on its pipe
/// write — Unix flow control); when it drains back to the low watermark
/// `onResume` is invoked. The handlers are called *inside the lock*, at the
/// same instant the paused state flips, so the decision and its application to
/// the PTY can never be reordered relative to each other across threads. The
/// handlers must therefore be cheap and non-blocking (DispatchSource
/// suspend/resume qualify) and MUST NOT call back into the coalescer.
///
/// Thread-safe: `append` is called from the background read pump, `drain` from
/// the main thread. A lock guards every access to mutable state.
final class PTYOutputCoalescer {
    /// Result of a `drain`. `hasMore` is true when the per-feed cap left bytes
    /// behind, so the caller reschedules until the buffer is empty.
    struct DrainResult: Equatable {
        let bytes: [UInt8]
        let hasMore: Bool
    }

    private let highWater: Int
    private let lowWater: Int
    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var flushScheduled = false
    private var producerPaused = false
    private var onPause: (() -> Void)?
    private var onResume: (() -> Void)?

    /// - Parameters:
    ///   - highWater: pause reading once `pending` reaches this many bytes.
    ///   - lowWater: resume reading once `pending` drops to this many bytes.
    ///     Must be strictly less than `highWater` so the hysteresis band is
    ///     non-empty and pause/resume can't thrash.
    init(highWater: Int = 4 * 1024 * 1024, lowWater: Int = 1 * 1024 * 1024) {
        precondition(highWater > lowWater, "highWater must exceed lowWater")
        self.highWater = highWater
        self.lowWater = lowWater
    }

    /// Install the backpressure handlers. Call once, before reading starts.
    func setBackpressureHandlers(onPause: @escaping () -> Void,
                                 onResume: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.onPause = onPause
        self.onResume = onResume
    }

    /// Append bytes from the background read pump.
    /// - Returns: `true` if the caller should schedule a main-thread drain
    ///   (i.e. no flush is already pending).
    @discardableResult
    func append(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pending.append(contentsOf: data)

        let scheduleFlush: Bool
        if flushScheduled {
            scheduleFlush = false
        } else {
            flushScheduled = true
            scheduleFlush = true
        }

        if !producerPaused && pending.count >= highWater {
            producerPaused = true
            onPause?()
        }

        return scheduleFlush
    }

    /// Drain up to `max` bytes (must be > 0). Keeps the scheduled flag set while
    /// bytes remain (so the caller reschedules), and invokes `onResume` when
    /// `pending` falls to the low watermark. Call on the main thread inside the
    /// scheduled flush.
    func drain(max: Int) -> DrainResult {
        precondition(max > 0, "drain cap must be positive")
        lock.lock()
        defer { lock.unlock() }
        let n = Swift.min(max, pending.count)
        let out = Array(pending[0..<n])
        pending.removeFirst(n)
        let more = !pending.isEmpty
        flushScheduled = more

        if producerPaused && pending.count <= lowWater {
            producerPaused = false
            onResume?()
        }

        return DrainResult(bytes: out, hasMore: more)
    }
}
