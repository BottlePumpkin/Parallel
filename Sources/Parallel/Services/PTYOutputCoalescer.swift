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
    /// Result of an `append`. `scheduleFlush` asks the caller to schedule one
    /// main-thread drain; `pauseProducer` fires once when `pending` first
    /// crosses the high watermark, asking the caller to stop reading the PTY.
    struct AppendOutcome: Equatable {
        let scheduleFlush: Bool
        let pauseProducer: Bool
    }

    /// Result of a `drain`. `hasMore` is true when the per-feed cap left bytes
    /// behind; `resumeProducer` fires once when `pending` falls back to the low
    /// watermark, asking the caller to resume reading the PTY.
    struct DrainResult: Equatable {
        let bytes: [UInt8]
        let hasMore: Bool
        let resumeProducer: Bool
    }

    private let highWater: Int
    private let lowWater: Int
    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var flushScheduled = false
    private var producerPaused = false

    /// - Parameters:
    ///   - highWater: pause reading once `pending` reaches this many bytes.
    ///   - lowWater: resume reading once `pending` drops to this many bytes.
    init(highWater: Int = 4 * 1024 * 1024, lowWater: Int = 1 * 1024 * 1024) {
        self.highWater = highWater
        self.lowWater = lowWater
    }

    /// Append bytes from the background read pump.
    func append(_ data: Data) -> AppendOutcome {
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

        var pauseProducer = false
        if !producerPaused && pending.count >= highWater {
            producerPaused = true
            pauseProducer = true
        }

        return AppendOutcome(scheduleFlush: scheduleFlush, pauseProducer: pauseProducer)
    }

    /// Drain up to `max` bytes. Keeps the scheduled flag set while bytes remain
    /// (so the caller reschedules), and signals resume when `pending` falls to
    /// the low watermark. Call on the main thread inside the scheduled flush.
    func drain(max: Int) -> DrainResult {
        lock.lock()
        defer { lock.unlock() }
        let n = Swift.min(Swift.max(max, 0), pending.count)
        let out = Array(pending[0..<n])
        pending.removeFirst(n)
        let more = !pending.isEmpty
        flushScheduled = more

        var resumeProducer = false
        if producerPaused && pending.count <= lowWater {
            producerPaused = false
            resumeProducer = true
        }

        return DrainResult(bytes: out, hasMore: more, resumeProducer: resumeProducer)
    }
}
