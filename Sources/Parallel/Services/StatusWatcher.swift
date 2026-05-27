import Foundation
import AppKit
import Observation

/// Periodically calls `git status` for each tracked worktree and writes the
/// result into `WorkspaceStore.statuses`.
///
/// Polls every 5 seconds while the app is active. Stops when the app loses
/// focus. Concurrency capped at 4 simultaneous git invocations to avoid
/// thrashing the disk on users with many worktrees.
@Observable
final class StatusWatcher {
    private let store: WorkspaceStore
    private let svc = WorktreeService()
    private var timer: Timer?
    private let semaphore = DispatchSemaphore(value: 4)
    private let queue = DispatchQueue(label: "parallel.statuswatcher", attributes: .concurrent)
    private var observersInstalled = false

    init(store: WorkspaceStore) {
        self.store = store
    }

    func start() {
        installObserversIfNeeded()
        startTimer()
        tick()  // immediate first pass
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
        let snapshot = store.worktrees
        for wt in snapshot {
            queue.async { [weak self] in
                guard let self else { return }
                self.semaphore.wait()
                defer { self.semaphore.signal() }
                do {
                    let s = try self.svc.status(at: wt.path)
                    DispatchQueue.main.async {
                        self.store.statuses[wt.id] = s
                    }
                } catch {
                    AppLogger.status.error("status failed for \(wt.path.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    DispatchQueue.main.async {
                        var s = self.store.statuses[wt.id] ?? WorktreeStatus()
                        s.lastError = error.localizedDescription
                        s.lastCheckedAt = Date()
                        self.store.statuses[wt.id] = s
                    }
                }
            }
        }
    }
}
