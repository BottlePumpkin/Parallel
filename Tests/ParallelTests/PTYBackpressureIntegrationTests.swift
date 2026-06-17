import XCTest
@testable import Parallel

/// End-to-end exercise of the coalescer ↔ PTY backpressure seam with a real
/// forked shell, replicating SessionManager's wiring. A bursty high-throughput
/// producer must cross the watermark (triggering at least one pause) yet still
/// deliver its entire output — no loss, no deadlock.
final class PTYBackpressureIntegrationTests: XCTestCase {

    private final class Counter {
        private let l = NSLock()
        private var v = 0
        func bump() { l.lock(); v += 1; l.unlock() }
        var value: Int { l.lock(); defer { l.unlock() }; return v }
    }

    func test_burstyProducer_drainsFullyUnderBackpressure() throws {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/sh", cwd: tmp) else {
            XCTFail("forkpty failed")
            return
        }

        // Tiny watermarks + cap so a single bursty write forces the pause/resume
        // cycle through the real read source.
        let coalescer = PTYOutputCoalescer(highWater: 2048, lowWater: 512)
        let pauses = Counter()
        coalescer.setBackpressureHandlers(
            onPause: { [weak pty] in pauses.bump(); pty?.pauseReading() },
            onResume: { [weak pty] in pty?.resumeReading() }
        )

        let received = NSMutableData()
        let lock = NSLock()
        let gotEnd = expectation(description: "end marker delivered")
        gotEnd.assertForOverFulfill = false

        // Drain on a dedicated serial queue: the app drains on the main run
        // loop, but the test must not depend on XCTest servicing the main queue
        // during `wait`. The coalescer is thread-agnostic (lock-guarded), so
        // this still exercises the seam: background append vs. another-thread
        // drain, with pause/resume applied under the coalescer's lock.
        let feedQueue = DispatchQueue(label: "test.feed")
        // PTYs run in cooked mode (ONLCR), so output newlines arrive as "\r\n".
        // Strip CR before matching so sentinels are newline-agnostic.
        func text() -> String {
            lock.lock(); defer { lock.unlock() }
            return (String(data: received as Data, encoding: .utf8) ?? "")
                .replacingOccurrences(of: "\r", with: "")
        }
        func scheduleFeed() {
            feedQueue.async {
                let r = coalescer.drain(max: 1024)
                if !r.bytes.isEmpty {
                    lock.lock(); received.append(Data(r.bytes)); lock.unlock()
                    if text().contains("DONEMARKER\n") { gotEnd.fulfill() }
                }
                if r.hasMore { scheduleFeed() }
            }
        }

        let source = pty.startReading(
            onData: { data in if coalescer.append(data) { scheduleFeed() } },
            onEOF: {}
        )

        // Disable echo (so the typed command can't satisfy the sentinel), then
        // burst 60 000 'X' bytes in one stream — a single flood that fills the
        // pipe and forces the high watermark — followed by a unique marker.
        pty.write("stty -echo\n".data(using: .utf8)!)
        pty.write("head -c 60000 /dev/zero | tr '\\0' X; printf '\\nDONEMARKER\\n'\n"
            .data(using: .utf8)!)

        wait(for: [gotEnd], timeout: 30.0)

        let body = text()
        let xCount = body.filter { $0 == "X" }.count
        XCTAssertGreaterThanOrEqual(xCount, 60000, "every burst byte must be delivered (no loss)")
        XCTAssertGreaterThan(pauses.value, 0,
                             "the burst should have crossed the high watermark")

        pty.write("exit\n".data(using: .utf8)!)
        Thread.sleep(forTimeInterval: 0.1)
        source.cancel()
        pty.terminate()
    }
}
