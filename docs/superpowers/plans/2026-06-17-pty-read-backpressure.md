# PTY Read Backpressure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound per-session memory under parallel high-throughput builds by suspending the PTY read source when the coalescer buffer is full and resuming when it drains, so producers self-throttle via kernel pipe flow control.

**Architecture:** `PTYOutputCoalescer` becomes a high/low-watermark state machine that signals pause/resume only on threshold transitions. `PTY` gains balanced `pauseReading()`/`resumeReading()` over its `DispatchSourceRead`. `SessionManager` wires the coalescer's signals to the PTY across the background-read / main-feed boundary.

**Tech Stack:** Swift, XCTest, Dispatch (`DispatchSourceRead` suspend/resume), SwiftTerm.

**Branch note:** This project commits directly to `master` (see git history). Continue on `master`, committing per task.

**Spec:** `docs/superpowers/specs/2026-06-17-pty-read-backpressure-design.md`

---

## File Structure

- **Modify** `Sources/Parallel/Services/PTYOutputCoalescer.swift` — change `append` return type to `AppendOutcome`, add `resumeProducer` to `DrainResult`, add injectable `highWater`/`lowWater` and `producerPaused` state.
- **Modify** `Tests/ParallelTests/PTYOutputCoalescerTests.swift` — adapt existing assertions to the new `append`/`drain` shapes; add watermark transition + hysteresis tests.
- **Modify** `Sources/Parallel/Services/PTY.swift` — add `pauseReading()`/`resumeReading()` with an `isPaused` guard; resume-before-cancel in `terminate()` and `deinit`.
- **Modify** `Tests/ParallelTests/PTYTests.swift` — add no-loss-across-pause/resume test and a redundant pause/resume balance test.
- **Modify** `Sources/Parallel/Services/SessionManager.swift` — wire `AppendOutcome.pauseProducer` → `pty.pauseReading()` and `DrainResult.resumeProducer` → `pty.resumeReading()`.

---

## Task 1: Coalescer watermark state machine

**Files:**
- Modify: `Sources/Parallel/Services/PTYOutputCoalescer.swift`
- Test: `Tests/ParallelTests/PTYOutputCoalescerTests.swift`

- [ ] **Step 1: Rewrite the test file (RED)**

Replace the entire contents of `Tests/ParallelTests/PTYOutputCoalescerTests.swift` with:

```swift
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

    /// Crossing the high watermark requests a producer pause exactly once.
    func test_appendCrossingHighWater_requestsPauseOnce() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        XCTAssertFalse(c.append(Data([0x01, 0x02, 0x03])).pauseProducer) // 3 < 8
        XCTAssertTrue(c.append(Data(repeating: 0x00, count: 5)).pauseProducer) // 8 >= 8
        XCTAssertFalse(c.append(Data([0x09])).pauseProducer) // already paused
    }

    /// Draining at/below the low watermark requests resume exactly once.
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

    /// Staying strictly between low and high emits no pause/resume (hysteresis).
    func test_betweenWatermarks_noPauseOrResume() {
        let c = PTYOutputCoalescer(highWater: 100, lowWater: 10)
        XCTAssertFalse(c.append(Data(repeating: 0x00, count: 50)).pauseProducer)
        XCTAssertFalse(c.drain(max: 20).resumeProducer) // 30 pending, never paused
    }

    /// Fully draining while paused requests resume (0 <= lowWater).
    func test_fullDrainWhilePaused_requestsResume() {
        let c = PTYOutputCoalescer(highWater: 8, lowWater: 4)
        _ = c.append(Data(repeating: 0x00, count: 8)) // pauses
        XCTAssertTrue(c.drain(max: 1024).resumeProducer)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep -i error: | head`
Expected: compile errors — `value of type 'Bool' has no member 'scheduleFlush'` and `extra argument 'highWater' in call` / no `pauseProducer` / `resumeProducer` members.

- [ ] **Step 3: Rewrite the coalescer (GREEN)**

Replace the body of `PTYOutputCoalescer` in `Sources/Parallel/Services/PTYOutputCoalescer.swift` (keep the file's leading doc comment; replace from `final class PTYOutputCoalescer {` to its closing brace) with:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PTYOutputCoalescerTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Services/PTYOutputCoalescer.swift Tests/ParallelTests/PTYOutputCoalescerTests.swift
git commit -m "feat(services): coalescer high/low-watermark backpressure signals"
```

---

## Task 2: PTY pause/resume reading

**Files:**
- Modify: `Sources/Parallel/Services/PTY.swift` (add fields near line 15-16; add methods; edit `terminate()` ~128 and `deinit` ~65)
- Test: `Tests/ParallelTests/PTYTests.swift`

- [ ] **Step 1: Add the failing tests (RED)**

Append these two methods inside `final class PTYTests: XCTestCase` in `Tests/ParallelTests/PTYTests.swift` (before the final closing brace):

```swift
    /// Output produced while reading is paused must not be lost — it stays in
    /// the kernel pipe and is delivered after resume.
    func test_pauseThenResume_deliversAllOutput() throws {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/sh", cwd: tmp) else {
            XCTFail("forkpty failed")
            return
        }
        let received = NSMutableData()
        let lock = NSLock()
        let gotMarker = expectation(description: "got END marker")
        gotMarker.assertForOverFulfill = false

        let source = pty.startReading(
            onData: { data in
                lock.lock()
                received.append(data)
                let text = String(data: received as Data, encoding: .utf8) ?? ""
                lock.unlock()
                if text.contains("END_MARKER_99") { gotMarker.fulfill() }
            },
            onEOF: {}
        )

        // Pause first, then generate a few KB of output. It accumulates in the
        // pipe; nothing is read until we resume.
        pty.pauseReading()
        pty.write("printf 'A%.0s' $(seq 1 5000); echo END_MARKER_99\n".data(using: .utf8)!)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            pty.resumeReading()
        }

        wait(for: [gotMarker], timeout: 5.0)

        pty.write("exit\n".data(using: .utf8)!)
        Thread.sleep(forTimeInterval: 0.1)
        source.cancel()
        pty.terminate()
    }

    /// Redundant pause/resume calls are guarded so the dispatch source's
    /// suspend count stays balanced and terminate() never crashes.
    func test_pauseResume_redundantCallsAreBalanced() {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/sh", cwd: tmp) else {
            XCTFail("forkpty failed")
            return
        }
        let source = pty.startReading(onData: { _ in }, onEOF: {})
        pty.pauseReading()
        pty.pauseReading()   // redundant — must be a no-op
        pty.resumeReading()
        pty.resumeReading()  // redundant — must be a no-op
        source.cancel()
        pty.terminate()      // must not crash
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep -i error: | head`
Expected: `value of type 'PTY' has no member 'pauseReading'` / `resumeReading`.

- [ ] **Step 3: Implement pause/resume and resume-before-cancel (GREEN)**

In `Sources/Parallel/Services/PTY.swift`:

(a) Add a state flag next to the existing `private var terminated = false` (line ~16):

```swift
    private var readPaused = false
```

(b) Replace the existing `deinit` (lines ~65-68):

```swift
    deinit {
        readSource?.cancel()
        close(masterFD)
    }
```

with:

```swift
    deinit {
        // A suspended dispatch source must be resumed before it is released,
        // or the runtime traps. Balance any outstanding pause first.
        if readPaused { readSource?.resume(); readPaused = false }
        readSource?.cancel()
        close(masterFD)
    }
```

(c) Add these methods immediately after `startReading(...)` returns (after its closing brace, ~line 122):

```swift
    /// Suspend the read source. Output keeps accumulating in the kernel pipe;
    /// once the pipe fills the child blocks on `write()` — natural flow
    /// control. Idempotent: a second call while paused is a no-op so the
    /// dispatch source's suspend count stays balanced.
    func pauseReading() {
        guard let source = readSource, !readPaused else { return }
        readPaused = true
        source.suspend()
    }

    /// Resume a paused read source. Idempotent: a no-op when not paused.
    func resumeReading() {
        guard let source = readSource, readPaused else { return }
        readPaused = false
        source.resume()
    }
```

(d) In `terminate()` (line ~128), resume a paused source first so later
`cancel()`/release is safe. Replace:

```swift
    func terminate() {
        if terminated { return }
        terminated = true
        kill(pid, SIGTERM)
```

with:

```swift
    func terminate() {
        if terminated { return }
        terminated = true
        if readPaused { resumeReading() }
        kill(pid, SIGTERM)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PTYTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 4 tests, with 0 failures` (2 existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Services/PTY.swift Tests/ParallelTests/PTYTests.swift
git commit -m "feat(services): PTY pauseReading/resumeReading with balanced suspend"
```

---

## Task 3: Wire backpressure into SessionManager

**Files:**
- Modify: `Sources/Parallel/Services/SessionManager.swift` (the `startReading` call inside `startSession`, ~lines 156-175)

- [ ] **Step 1: Update the read-pump wiring**

In `Sources/Parallel/Services/SessionManager.swift`, replace this block:

```swift
        let coalescer = PTYOutputCoalescer()
        func scheduleFeed() {
            DispatchQueue.main.async {
                let r = coalescer.drain(max: Self.feedBytesPerHop)
                if !r.bytes.isEmpty {
                    view.feed(byteArray: ArraySlice(r.bytes))
                }
                if r.hasMore { scheduleFeed() }
            }
        }
        entry.readSource = pty.startReading(
            onData: { data in
                if coalescer.append(data) { scheduleFeed() }
            },
```

with:

```swift
        let coalescer = PTYOutputCoalescer()
        func scheduleFeed() {
            DispatchQueue.main.async {
                let r = coalescer.drain(max: Self.feedBytesPerHop)
                if !r.bytes.isEmpty {
                    view.feed(byteArray: ArraySlice(r.bytes))
                }
                // Buffer drained back to the low watermark — let the producer run.
                if r.resumeProducer { pty.resumeReading() }
                if r.hasMore { scheduleFeed() }
            }
        }
        entry.readSource = pty.startReading(
            onData: { data in
                let outcome = coalescer.append(data)
                // Buffer hit the high watermark — stop reading so the build
                // blocks on its pipe instead of growing our memory unbounded.
                if outcome.pauseProducer { pty.pauseReading() }
                if outcome.scheduleFlush { scheduleFeed() }
            },
```

- [ ] **Step 2: Build and run the full suite**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

Run: `swift test 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests"`
Expected: `'All tests' passed` and the final `Executed N tests, with 0 failures` (≈ 83 tests).

- [ ] **Step 3: Commit**

```bash
git add Sources/Parallel/Services/SessionManager.swift
git commit -m "fix(services): apply PTY read backpressure from coalescer watermarks"
```

---

## Self-Review Notes

- **Spec coverage:** watermark state machine (Task 1), PTY pause/resume + suspended-source safety (Task 2), SessionManager wiring across the read/feed boundary (Task 3) — all spec sections covered.
- **Type consistency:** `AppendOutcome { scheduleFlush, pauseProducer }` and `DrainResult { bytes, hasMore, resumeProducer }` are used identically in tests (Task 1) and wiring (Task 3). `pauseReading()`/`resumeReading()` names match across Task 2 and Task 3.
- **Manual runtime check (post-implementation):** run an iOS build in a worktree terminal; confirm no beachball and that `Parallel`'s memory stays bounded (Activity Monitor) while the build's CPU dips when the buffer is full (producer throttled).
