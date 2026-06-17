# PTY Read Backpressure — Design

**Date:** 2026-06-17
**Status:** Approved, pending implementation

## Problem

Parallel hangs (beachball → force quit) when a worktree terminal runs a
high-throughput producer such as an iOS build (`xcodebuild`). Root cause: PTY
output was fed to SwiftTerm one `DispatchQueue.main.async { view.feed }` per
read chunk, so the background reader outran the main thread's parse+render and
the main queue backlog grew unbounded.

Two fixes already landed:

- `02f2561` — coalesce output into one main-thread feed per scheduling cycle.
- `dc4c2b1` — cap each feed at 256 KB/hop so one burst can't freeze a frame.

These convert "hang" into "graceful lag". One risk remains: with **parallel
builds across multiple worktrees** (a core use case), the coalescer's pending
buffer can still grow without bound when producers collectively outrun the
single main thread — a memory/OOM risk.

## Constraints

- SwiftTerm `TerminalView.feed()` must run on the **main thread** (mutates the
  terminal buffer + triggers display).
- Bytes **cannot be dropped** — scrollback and escape-sequence parsing require
  the full, in-order byte stream.
- The main thread is serial: under sustained N-producer overload, undelivered
  bytes must be buffered *somewhere*. Today that "somewhere" is unbounded.

## Approach: read backpressure with high/low watermarks

When the coalescer's pending buffer exceeds a high watermark, **suspend the PTY
read source**. The kernel pipe fills, the child process blocks on `write()`
(standard Unix flow control), and the producer self-throttles. When the main
thread drains the buffer below a low watermark, **resume** reading. Hysteresis
between the two watermarks prevents suspend/resume thrashing.

This bounds per-session memory, drops no data, and makes each parallel build
throttle itself independently.

## Components

### `PTYOutputCoalescer` (extend — pure state machine)

New state: `producerPaused: Bool`. New config (injectable; defaults
`highWater = 4 MB`, `lowWater = 1 MB`):

- `append(_ data: Data) -> AppendOutcome`
  - `AppendOutcome { scheduleFlush: Bool, pauseProducer: Bool }`
  - `scheduleFlush`: true when no flush was already scheduled (unchanged
    behaviour from today's `append` boolean).
  - `pauseProducer`: true **only on the transition** `pending` crosses
    `highWater` while not already paused; sets `producerPaused = true`.
- `drain(max: Int) -> DrainResult`
  - `DrainResult { bytes: [UInt8], hasMore: Bool, resumeProducer: Bool }`
  - `hasMore` / cap behaviour unchanged from today.
  - `resumeProducer`: true **only on the transition** to
    `pending <= lowWater` while paused; sets `producerPaused = false`.

The coalescer emits pause/resume **only on transitions**, so the consumer
receives exactly balanced suspend/resume calls.

### `PTY` (extend)

- `pauseReading()` / `resumeReading()` — `suspend()` / `resume()` the internal
  `DispatchSourceRead`, guarded by an `isPaused` flag to keep the suspend count
  balanced even if called redundantly.
- Safety: a suspended `DispatchSource` must not be released. `terminate()` and
  `deinit` must **resume before cancel** if currently paused.

### `SessionManager` (wire)

- `onData` (background read queue):
  ```
  let outcome = coalescer.append(data)
  if outcome.pauseProducer { pty.pauseReading() }
  if outcome.scheduleFlush { scheduleFeed() }
  ```
- `scheduleFeed` (main):
  ```
  let r = coalescer.drain(max: feedBytesPerHop)
  if !r.bytes.isEmpty { view.feed(byteArray: ArraySlice(r.bytes)) }
  if r.resumeProducer { pty.resumeReading() }
  if r.hasMore { scheduleFeed() }
  ```

## Data flow under overload

```
build floods → background read → coalescer.append
  → pending > 4MB → pauseReading() → kernel pipe fills
  → child blocks in write() (natural throttle) ✋
main: drain 256KB/hop, repeat → pending ≤ 1MB
  → resumeReading() → build proceeds ▶
```

No data loss · per-session memory ceiling ~4 MB · no hang/OOM.

## Thread safety

- `append` runs inside the read source's own handler (background); suspending
  the source from within its handler takes effect after the handler returns —
  safe.
- `resume()` is called from the main thread; `DispatchSource` suspend/resume
  are thread-safe.
- Because pause/resume are emitted only on transitions, suspend/resume calls
  stay balanced.

## Testing (TDD)

**Coalescer (pure, fast):**
- `append` crossing `highWater` returns `pauseProducer` once; not again while
  paused.
- `drain` crossing `lowWater` returns `resumeProducer` once.
- Values between low and high produce no pause/resume signal (hysteresis).
- Fully draining while paused returns `resumeProducer`.
- Existing cap / coalesce / schedule tests still pass.

**PTY (integration):**
- Fork a real shell emitting more than `highWater` bytes; assert that after the
  pause/resume cycle **every byte is eventually delivered** (no loss).

## Out of scope

- Visibility-based deferral of hidden tabs (memory risk, murky benefit).
- Moving terminal parsing off the main thread (not supported by SwiftTerm).
