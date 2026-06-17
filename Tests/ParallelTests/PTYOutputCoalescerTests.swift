import XCTest
@testable import Parallel

/// `PTYOutputCoalescer` collapses many small PTY read chunks into a small
/// number of capped main-thread feeds, and applies high/low-watermark
/// backpressure so a producer that outruns the main thread is throttled
/// instead of buffered without bound. Watermarks are injected small here so
/// transitions are deterministic.
final class PTYOutputCoalescerTests: XCTestCase {

    // MARK: Scheduling

    func test_firstAppend_signalsScheduleFlush() {
        let c = PTYOutputCoalescer()
        XCTAssertTrue(c.append(Data([0x61])).scheduleFlush)
    }

    func test_appendWhilePending_doesNotRescheduleFlush() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        XCTAssertFalse(c.append(Data([0x62])).scheduleFlush)
        XCTAssertFalse(c.append(Data([0x63])).scheduleFlush)
    }

    func test_appendAfterFullDrain_signalsScheduleAgain() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        _ = c.drain(max: 1024)
        XCTAssertTrue(c.append(Data([0x62])).scheduleFlush)
    }

    // MARK: Cap / coalesce

    func test_drain_underCap_returnsAllBytesInOrderNoMore() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61, 0x62]))
        _ = c.append(Data([0x63]))
        let r = c.drain(max: 1024)
        XCTAssertEqual(r.bytes, [0x61, 0x62, 0x63])
        XCTAssertFalse(r.hasMore)
    }

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

    func test_drainWhenEmpty_returnsEmptyNoMore() {
        let c = PTYOutputCoalescer()
        let r = c.drain(max: 1024)
        XCTAssertTrue(r.bytes.isEmpty)
        XCTAssertFalse(r.hasMore)
    }

    func test_drain_includesBytesAppendedAfterScheduling() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        _ = c.append(Data([0x62]))
        XCTAssertEqual(c.drain(max: 1024).bytes, [0x61, 0x62])
    }

    // MARK: Backpressure (high/low watermark)

    func test_appendCrossingHighWater_requestsPauseOnce() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        XCTAssertFalse(c.append(Data([0x01, 0x02, 0x03])).pauseProducer) // 3 < 8
        XCTAssertTrue(c.append(Data(repeating: 0x00, count: 5)).pauseProducer) // 8 >= 8
        XCTAssertFalse(c.append(Data([0x09])).pauseProducer) // already paused
    }

    func test_drainCrossingLowWater_requestsResumeOnce() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        _ = c.append(Data(repeating: 0x00, count: 8)) // pauses (8 >= 8)
        let first = c.drain(max: 2) // 6 pending, > 4 → no resume yet
        XCTAssertFalse(first.resumeProducer)
        let second = c.drain(max: 3) // 3 pending, <= 4 → resume
        XCTAssertTrue(second.resumeProducer)
        let third = c.drain(max: 3) // already resumed
        XCTAssertFalse(third.resumeProducer)
    }

    func test_betweenWatermarks_noPauseOrResume() {
        let c = PTYOutputCoalescer(highWater: 100, lowWater: 10)
        XCTAssertFalse(c.append(Data(repeating: 0x00, count: 50)).pauseProducer)
        XCTAssertFalse(c.drain(max: 20).resumeProducer) // 30 pending, never paused
    }

    func test_fullDrainWhilePaused_requestsResume() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        _ = c.append(Data(repeating: 0x00, count: 8)) // pauses
        XCTAssertTrue(c.drain(max: 1024).resumeProducer)
    }
}
