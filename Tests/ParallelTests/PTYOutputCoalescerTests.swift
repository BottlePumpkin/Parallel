import XCTest
@testable import Parallel

/// `PTYOutputCoalescer` collapses many small PTY read chunks into a small
/// number of capped feeds, and applies high/low-watermark backpressure by
/// invoking pause/resume handlers *inside its lock* at the moment the buffer
/// crosses a watermark — so the decision and its application can never be
/// reordered across threads. Watermarks are injected small here so transitions
/// are deterministic.
final class PTYOutputCoalescerTests: XCTestCase {

    /// Records pause/resume callbacks for assertions.
    private final class Spy {
        var pauses = 0
        var resumes = 0
        func attach(to c: PTYOutputCoalescer) {
            c.setBackpressureHandlers(
                onPause: { self.pauses += 1 },
                onResume: { self.resumes += 1 }
            )
        }
    }

    // MARK: Scheduling

    func test_firstAppend_signalsScheduleFlush() {
        let c = PTYOutputCoalescer()
        XCTAssertTrue(c.append(Data([0x61])))
    }

    func test_appendWhilePending_doesNotRescheduleFlush() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        XCTAssertFalse(c.append(Data([0x62])))
        XCTAssertFalse(c.append(Data([0x63])))
    }

    func test_appendAfterFullDrain_signalsScheduleAgain() {
        let c = PTYOutputCoalescer()
        _ = c.append(Data([0x61]))
        _ = c.drain(max: 1024)
        XCTAssertTrue(c.append(Data([0x62])))
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

    func test_appendCrossingHighWater_pausesOnce() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        let spy = Spy(); spy.attach(to: c)
        _ = c.append(Data([0x01, 0x02, 0x03])) // 3 < 8
        XCTAssertEqual(spy.pauses, 0)
        _ = c.append(Data(repeating: 0x00, count: 5)) // 8 >= 8 → pause
        XCTAssertEqual(spy.pauses, 1)
        _ = c.append(Data([0x09])) // already paused → no second pause
        XCTAssertEqual(spy.pauses, 1)
    }

    func test_drainCrossingLowWater_resumesOnce() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        let spy = Spy(); spy.attach(to: c)
        _ = c.append(Data(repeating: 0x00, count: 8)) // pauses (8 >= 8)
        _ = c.drain(max: 2) // 6 pending, > 4 → no resume yet
        XCTAssertEqual(spy.resumes, 0)
        _ = c.drain(max: 3) // 3 pending, <= 4 → resume
        XCTAssertEqual(spy.resumes, 1)
        _ = c.drain(max: 3) // already resumed
        XCTAssertEqual(spy.resumes, 1)
    }

    func test_betweenWatermarks_noPauseOrResume() {
        let c = PTYOutputCoalescer(highWater: 100, lowWater: 10)
        let spy = Spy(); spy.attach(to: c)
        _ = c.append(Data(repeating: 0x00, count: 50)) // 50 < 100
        _ = c.drain(max: 20) // 30 pending, never paused
        XCTAssertEqual(spy.pauses, 0)
        XCTAssertEqual(spy.resumes, 0)
    }

    func test_fullDrainWhilePaused_resumes() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        let spy = Spy(); spy.attach(to: c)
        _ = c.append(Data(repeating: 0x00, count: 8)) // pauses
        _ = c.drain(max: 1024) // fully drained, 0 <= 4 → resume
        XCTAssertEqual(spy.resumes, 1)
    }

    /// The drain chain keeps reporting `hasMore` while the producer is paused,
    /// guaranteeing the buffer can always drain back to the resume threshold.
    func test_pausedBufferStillDrainsViaHasMore() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        let spy = Spy(); spy.attach(to: c)
        _ = c.append(Data(repeating: 0x00, count: 10)) // pauses, 10 pending
        let first = c.drain(max: 2)  // 8 pending
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(spy.resumes, 0)
        let second = c.drain(max: 2) // 6 pending
        XCTAssertTrue(second.hasMore)
        _ = c.drain(max: 3)  // 3 pending <= 4 → resume
        XCTAssertEqual(spy.resumes, 1)
    }
}
