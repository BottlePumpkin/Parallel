import XCTest
@testable import Parallel

/// `PTYOutputCoalescer` collapses many small PTY read chunks into a single
/// main-thread feed. These tests pin the threading-agnostic core: the
/// "schedule once" signal and the drain/coalesce semantics that let a
/// high-throughput producer (e.g. an iOS build) avoid flooding the main queue.
final class PTYOutputCoalescerTests: XCTestCase {

    /// The first append after construction must tell the caller to schedule a
    /// flush — otherwise nothing ever drains.
    func test_firstAppend_signalsScheduleFlush() {
        let c = PTYOutputCoalescer()
        XCTAssertTrue(c.append(Data([0x61])))
    }

    /// While a flush is already pending, further appends must NOT request
    /// another schedule. This is the whole point: N chunks → 1 main-queue hop.
    func test_appendWhilePending_doesNotRescheduleFlush() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        XCTAssertFalse(c.append(Data([0x62])))
        XCTAssertFalse(c.append(Data([0x63])))
    }

    /// Drain returns every byte appended since the last drain, in order.
    func test_drain_returnsAllAppendedBytesInOrder() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61, 0x62]))
        _ = c.append(Data([0x63]))
        XCTAssertEqual(c.drain(), [0x61, 0x62, 0x63])
    }

    /// After a drain, the pending flag resets so the next append re-schedules.
    func test_appendAfterDrain_signalsScheduleAgain() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        _ = c.drain()
        XCTAssertTrue(c.append(Data([0x62])))
    }

    /// Draining with nothing pending yields empty (and is safe to call).
    func test_drainWhenEmpty_returnsEmpty() {
        let c = PTYOutputCoalescer()
        XCTAssertTrue(c.drain().isEmpty)
    }

    /// Bytes that arrive between scheduling and the flush running are still
    /// picked up by that flush's drain — no output is stranded.
    func test_drain_includesBytesAppendedAfterScheduling() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))   // schedules
        _ = c.append(Data([0x62]))   // arrives before flush runs
        XCTAssertEqual(c.drain(), [0x61, 0x62])
    }
}
