import Foundation
import AppKit
import Observation

/// Periodically calls `git status` for each tracked worktree and writes the
/// result into `WorkspaceStore.statuses`.
///
/// Polls every 5 seconds while the app is active. Stops when the app loses
/// focus. Concurrency is capped at 4 via an `OperationQueue`.
///
/// Why an OperationQueue and not a concurrent DispatchQueue + semaphore: the
/// old design did `queue.async { semaphore.wait(); git status }` per worktree
/// every tick. When `git status` is slow (e.g. while an Xcode build churns the
/// working tree) the four slots stall, yet every 5s tick enqueues another batch
/// — and on a *concurrent* queue each block parked in `semaphore.wait()` pins
/// its own GCD worker thread. The pool explodes (observed: 80 threads), the
/// global pool is exhausted, the PTY read pump can't get a thread, and the
/// terminal freezes (you can't even type). An OperationQueue holds queued work
/// as objects, not threads, so at most `maxConcurrentOperationCount` threads
/// ever exist regardless of how slow the work is.
@Observable
final class StatusWatcher {
    private let store: WorkspaceStore
    private let svc = WorktreeService()
    private var timer: Timer?
    private let opQueue: OperationQueue
    private var observersInstalled = false

    init(store: WorkspaceStore) {
        self.store = store
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        self.opQueue = q
    }

    func start() {
        installObserversIfNeeded()
        startTimer()
        tick()  // immediate first pass
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        opQueue.cancelAllOperations()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(appActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appInactive),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func appActive() {
        startTimer()
        tick()
    }
    @objc private func appInactive() {
        stop()
    }

    private func tick() {
        // Coalesce: skip this tick while the previous batch is still draining.
        // Slow git can outlast the 5s interval; without this guard each tick
        // piles another batch onto the queue until work never catches up.
        guard opQueue.operationCount == 0 else { return }
        let snapshot = store.worktrees
        for wt in snapshot {
            opQueue.addOperation { [weak self] in
                guard let self else { return }
                do {
                    let s = try self.svc.status(at: wt.path)
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        // Skip the write if the value didn't change — otherwise
                        // every 5s tick triggers a sidebar re-render even when
                        // nothing actually moved.
                        guard self.store.statuses[wt.id] != s else { return }
                        self.store.statuses[wt.id] = s
                    }
                } catch {
                    AppLogger.status.error("status failed for \(wt.path.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        var s = self.store.statuses[wt.id] ?? WorktreeStatus()
                        s.lastError = error.localizedDescription
                        s.lastCheckedAt = Date()
                        guard self.store.statuses[wt.id] != s else { return }
                        self.store.statuses[wt.id] = s
                    }
                }
            }
        }
    }
}
