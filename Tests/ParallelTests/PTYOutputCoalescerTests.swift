import XCTest
@testable import Parallel

/// `PTYOutputCoalescer` collapses many small PTY read chunks into a small
/// number of main-thread feeds. These tests pin the threading-agnostic core:
/// the "schedule once" signal, the drain/coalesce semantics, and the per-feed
/// cap that keeps a single huge burst (e.g. an iOS build) from monopolising
/// one frame on the main thread.
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

    /// A drain whose cap exceeds the pending size returns everything in order
    /// and reports no leftover.
    func test_drain_underCap_returnsAllBytesInOrderNoMore() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61, 0x62]))
        _ = c.append(Data([0x63]))
        let r = c.drain(max: 1024)
        XCTAssertEqual(r.bytes, [0x61, 0x62, 0x63])
        XCTAssertFalse(r.hasMore)
    }

    /// A drain caps the returned bytes; the remainder stays pending and is
    /// reported via `hasMore` so the caller schedules a follow-up feed.
    func test_drain_overCap_capsBytesAndReportsMore() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61, 0x62, 0x63, 0x64, 0x65]))
        let first = c.drain(max: 2)
        XCTAssertEqual(first.bytes, [0x61, 0x62])
        XCTAssertTrue(first.hasMore)

        let second = c.drain(max: 2)
        XCTAssertEqual(second.bytes, [0x63, 0x64])
        XCTAssertTrue(second.hasMore)

        let third = c.drain(max: 2)
        XCTAssertEqual(third.bytes, [0x65])
        XCTAssertFalse(third.hasMore)
    }

    /// After a fully-draining flush, the pending flag resets so the next
    /// append re-schedules.
    func test_appendAfterFullDrain_signalsScheduleAgain() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        _ = c.drain(max: 1024)
        XCTAssertTrue(c.append(Data([0x62])))
    }

    /// After a capped drain that left bytes behind, the flush is still
    /// considered scheduled (the caller keeps draining via `hasMore`), so a
    /// concurrent append must NOT request another schedule.
    func test_appendAfterCappedDrain_doesNotReschedule() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61, 0x62, 0x63]))
        let r = c.drain(max: 1)
        XCTAssertTrue(r.hasMore)
        XCTAssertFalse(c.append(Data([0x64])))
    }

    /// Draining with nothing pending yields empty + no-more (and is safe).
    func test_drainWhenEmpty_returnsEmptyNoMore() {
        let c = PTYOutputCoalescer()
        let r = c.drain(max: 1024)
        XCTAssertTrue(r.bytes.isEmpty)
        XCTAssertFalse(r.hasMore)
    }

    /// Bytes that arrive between scheduling and the flush running are still
    /// picked up by that flush's drain — no output is stranded.
    func test_drain_includesBytesAppendedAfterScheduling() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))   // schedules
        _ = c.append(Data([0x62]))   // arrives before flush runs
        XCTAssertEqual(c.drain(max: 1024).bytes, [0x61, 0x62])
    }
}
