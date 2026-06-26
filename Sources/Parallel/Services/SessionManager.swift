import Foundation
import SwiftTerm
import Observation
import AppKit

/// Owns one or more PTY + TerminalView pairs per worktree (tabs).
///
/// Thread contract: all mutating methods MUST be called on the main thread.
/// Callbacks from the underlying PTY's background read pump are routed back
/// to main before any state mutation.
@Observable
final class SessionManager {

    /// Max bytes fed to a terminal per main-thread hop. Caps how long one
    /// feed can run so a burst (e.g. an iOS build) is processed across
    /// several runloop turns instead of freezing one frame. 256 KB ≈ a few ms
    /// of parse work, and at 60 Hz drains ~15 MB/s — well above any build log.
    static let feedBytesPerHop = 256 * 1024

    /// Index to activate when cycling `forward` (or backward) through `count`
    /// tabs from `current`, wrapping around. nil when there are no tabs. Pure
    /// math, unit-tested independently of any live PTY.
    static func adjacentTabIndex(from current: Int, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        let delta = forward ? 1 : -1
        return ((current + delta) % count + count) % count
    }

    // MARK: - Terminal font sizing (⌘+ / ⌘- / ⌘0)

    /// Default terminal point size and the bounds the user can zoom within.
    static let defaultFontSize: CGFloat = 13
    static let minFontSize: CGFloat = 8
    static let maxFontSize: CGFloat = 32
    /// One ⌘+ / ⌘- step.
    static let fontSizeStep: CGFloat = 1
    /// UserDefaults key the chosen size is persisted under.
    static let fontSizeDefaultsKey = "terminalFontSize"

    /// Clamp a point size into `[minFontSize, maxFontSize]`. Pure, unit-tested.
    static func clampedFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, minFontSize), maxFontSize)
    }

    /// Next size when stepping `current` by `delta`, clamped to the bounds.
    /// Pure math, unit-tested independently of any live TerminalView.
    static func steppedFontSize(from current: CGFloat, delta: CGFloat) -> CGFloat {
        clampedFontSize(current + delta)
    }

    /// sessionId → entry. The single source of truth for live sessions.
    private var sessionsById: [UUID: SessionEntry] = [:]
    /// worktreeId → ordered list of sessionIds (tab order).
    private var orderByWorktree: [UUID: [UUID]] = [:]
    /// worktreeId → active sessionId in its tab strip.
    private var activeByWorktree: [UUID: UUID] = [:]

    /// Persistence backend for tab specs (count + label). Set by ParallelApp
    /// after both store and sessionManager are constructed. Weak-ish (strong
    /// here is fine since they share the app's lifetime).
    var store: WorkspaceStore?

    /// Current terminal point size, applied to every live `TerminalView`.
    /// Seeded from the persisted value (falling back to `defaultFontSize`) and
    /// updated by the ⌘+ / ⌘- / ⌘0 commands. `@Observable` so the e2e probe and
    /// any size-dependent UI re-render on change.
    private(set) var terminalFontSize: CGFloat = SessionManager.loadPersistedFontSize()

    private static func loadPersistedFontSize() -> CGFloat {
        // E2E runs must be hermetic: the size lives in standard UserDefaults
        // (not the isolated support dir), so always start from the default
        // there rather than leak a size between test runs.
        guard !TestMode.isE2E() else { return defaultFontSize }
        let stored = UserDefaults.standard.double(forKey: fontSizeDefaultsKey)
        return stored > 0 ? clampedFontSize(CGFloat(stored)) : defaultFontSize
    }

    /// `SessionEntry` is a class so the delegate, pty, and view share one
    /// lifetime and we don't need a parallel retain dict. SwiftTerm's
    /// `TerminalView` holds the delegate weakly, so the strong reference
    /// must live somewhere — here. `@Observable` so mutations to `label`
    /// re-render the tab bar.
    @Observable
    final class SessionEntry {
        let session: Session
        let pty: PTY
        let terminalView: TerminalView
        var readSource: DispatchSourceRead?
        var pendingSetupCommands: [String]
        let delegate: SessionTerminalDelegate
        /// Captured at start so exit notifications don't need to re-look up
        /// the worktree (which may have been renamed or untracked by then).
        let worktreeDisplayName: String
        let worktreeBranch: String
        /// User-set tab label. nil → use "shell N" auto label. Not persisted.
        var label: String?

        init(session: Session, pty: PTY, terminalView: TerminalView,
             readSource: DispatchSourceRead?, pendingSetupCommands: [String],
             delegate: SessionTerminalDelegate,
             worktreeDisplayName: String, worktreeBranch: String) {
            self.session = session
            self.pty = pty
            self.terminalView = terminalView
            self.readSource = readSource
            self.pendingSetupCommands = pendingSetupCommands
            self.delegate = delegate
            self.worktreeDisplayName = worktreeDisplayName
            self.worktreeBranch = worktreeBranch
            self.label = nil
        }
    }

    // MARK: - Lookups

    /// Tabs for a worktree, in order.
    func sessions(for worktreeId: UUID) -> [SessionEntry] {
        (orderByWorktree[worktreeId] ?? []).compactMap { sessionsById[$0] }
    }

    /// Active session in a worktree's tab strip, if any. Returns the live
    /// entry the UI should draw.
    func activeSession(for worktreeId: UUID) -> SessionEntry? {
        guard let sid = activeByWorktree[worktreeId] else { return nil }
        return sessionsById[sid]
    }

    /// Backward-compatible alias used by UI code that doesn't care which tab.
    func session(for worktreeId: UUID) -> SessionEntry? {
        activeSession(for: worktreeId)
    }

    /// All currently-running sessions across all worktrees. TerminalPaneView
    /// keeps every one continuously mounted in a ZStack so worktree/tab
    /// switches don't reparent SwiftTerm's NSView.
    var allRunningSessions: [SessionEntry] {
        sessionsById.values.filter {
            if case .running = $0.session.state { return true }
            return false
        }
    }

    // MARK: - Mutations

    /// Return active session for the worktree. On first visit after restart,
    /// rehydrate any persisted tab specs (count + labels) by forking that
    /// many PTYs.
    @discardableResult
    func ensureSession(for worktree: Worktree, setupCommands: [String] = []) -> SessionEntry? {
        dispatchPrecondition(condition: .onQueue(.main))
        if let e = activeSession(for: worktree.id) { return e }

        // Restore persisted tabs if any.
        let specs = store?.tabSpecs(for: worktree.id) ?? []
        if !specs.isEmpty {
            var first: SessionEntry?
            for spec in specs {
                let e = startSession(for: worktree, setupCommands: setupCommands, persistSpec: false)
                e?.label = spec.label
                if first == nil { first = e }
            }
            return first
        }

        return startSession(for: worktree, setupCommands: setupCommands)
    }

    /// Start a new tab in the worktree's strip and make it active.
    @discardableResult
    func startSession(for worktree: Worktree, setupCommands: [String], persistSpec: Bool = true) -> SessionEntry? {
        dispatchPrecondition(condition: .onQueue(.main))
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let pty = PTY(shell: shell, cwd: worktree.path) else {
            AppLogger.session.error("PTY fork failed for \(worktree.displayName, privacy: .public)")
            return nil
        }
        AppLogger.session.info("start \(worktree.displayName, privacy: .public) pid=\(pty.pid)")

        let view = ParallelTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.font = Self.terminalFont(size: terminalFontSize)
        // SwiftTerm's default scrollback is 500 lines and Buffer.resize
        // trims oldest rows whenever the grid shrinks. ZStack frame changes
        // during worktree / tab switches were silently truncating the
        // scrollback. 10 000 lines gives plenty of headroom (~1.6 MB per
        // session at 80 cols) so trims never reach existing history.
        view.getTerminal().changeScrollback(10_000)
        let delegate = SessionTerminalDelegate(pty: pty)
        view.terminalDelegate = delegate

        let session = Session(worktreeId: worktree.id, pid: pty.pid)
        let entry = SessionEntry(
            session: session,
            pty: pty,
            terminalView: view,
            readSource: nil,
            pendingSetupCommands: setupCommands,
            delegate: delegate,
            worktreeDisplayName: worktree.displayName,
            worktreeBranch: worktree.branch
        )

        let sessionId = session.id
        // Coalesce PTY output: high-throughput producers (iOS builds) emit
        // megabytes that would otherwise flood the main queue with one
        // `feed` block per read chunk, saturating the main thread and
        // beachballing the app. Accumulate on the background pump and drain
        // on the main thread, capped per hop so one giant burst can't
        // monopolise a single frame — leftover reschedules itself.
        let coalescer = PTYOutputCoalescer()
        // Backpressure: the coalescer suspends/resumes the PTY read source
        // itself, atomically with its watermark transitions, so a build that
        // outruns the main thread blocks on its pipe instead of growing our
        // buffer unbounded. weak to avoid a readSource → coalescer → pty cycle.
        coalescer.setBackpressureHandlers(
            onPause: { [weak pty] in pty?.pauseReading() },
            onResume: { [weak pty] in pty?.resumeReading() }
        )
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
            onEOF: { [weak self] in
                DispatchQueue.main.async {
                    self?.markExited(sessionId: sessionId)
                }
            }
        )

        sessionsById[sessionId] = entry
        orderByWorktree[worktree.id, default: []].append(sessionId)
        activeByWorktree[worktree.id] = sessionId

        if persistSpec {
            store?.appendTabSpec(worktreeId: worktree.id, label: nil)
        }

        if !setupCommands.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.flushSetupCommands(sessionId: sessionId)
            }
        }

        return entry
    }

    /// Rename a tab. Empty/whitespace input clears the custom label
    /// (falling back to "shell N").
    func renameSession(sessionId: UUID, to newLabel: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let e = sessionsById[sessionId] else { return }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        e.label = trimmed.isEmpty ? nil : trimmed
        let wid = e.session.worktreeId
        if let idx = orderByWorktree[wid]?.firstIndex(of: sessionId) {
            store?.updateTabSpec(worktreeId: wid, at: idx, label: e.label)
        }
    }

    /// Mark a specific tab as the active one in its worktree.
    func setActive(sessionId: UUID, in worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let order = orderByWorktree[worktreeId], order.contains(sessionId) else { return }
        guard activeByWorktree[worktreeId] != sessionId else { return }
        activeByWorktree[worktreeId] = sessionId
    }

    /// Cycle the active tab in a worktree's strip (⌃Tab / ⌃⇧Tab).
    func activateAdjacentTab(in worktreeId: UUID, forward: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let order = orderByWorktree[worktreeId], !order.isEmpty else { return }
        let currentIdx = activeByWorktree[worktreeId].flatMap { order.firstIndex(of: $0) } ?? 0
        guard let nextIdx = Self.adjacentTabIndex(from: currentIdx, count: order.count, forward: forward) else { return }
        guard activeByWorktree[worktreeId] != order[nextIdx] else { return }
        activeByWorktree[worktreeId] = order[nextIdx]
    }

    /// Activate the tab at `index` (0-based) in a worktree's strip, if present (⌘1–9).
    func activateTab(in worktreeId: UUID, at index: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let order = orderByWorktree[worktreeId], index >= 0, index < order.count else { return }
        guard activeByWorktree[worktreeId] != order[index] else { return }
        activeByWorktree[worktreeId] = order[index]
    }

    /// Clear the active tab's screen + scrollback (⌘K). Display-side only: the
    /// shell is NOT sent anything, so a running program isn't disturbed. ESC[H
    /// home, ESC[2J erase screen, ESC[3J erase scrollback.
    func clearActiveTerminal(in worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let view = activeSession(for: worktreeId)?.terminalView else { return }
        let seq: [UInt8] = Array("\u{1b}[H\u{1b}[2J\u{1b}[3J".utf8)
        view.feed(byteArray: seq[...])
    }

    /// Show SwiftTerm's built-in find bar on the active tab (⌘F). Uses the
    /// public performTextFinderAction entry point; showFindBar is private.
    func showFind(in worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let view = activeSession(for: worktreeId)?.terminalView else { return }
        let item = NSMenuItem()
        item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue) // rawValue is UInt; tag is Int — safe on 64-bit macOS
        view.performTextFinderAction(item)
    }

    /// Terminate a single tab. If it was active, advance active to the
    /// next tab in the strip (or previous if it was the last).
    func terminate(sessionId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let entry = sessionsById[sessionId] else { return }
        let worktreeId = entry.session.worktreeId
        AppLogger.session.info("terminate session=\(sessionId, privacy: .public) pid=\(entry.pty.pid)")
        entry.pty.terminate()
        entry.readSource?.cancel()
        sessionsById.removeValue(forKey: sessionId)

        var order = orderByWorktree[worktreeId] ?? []
        var removedIndex: Int?
        if let idx = order.firstIndex(of: sessionId) {
            removedIndex = idx
            order.remove(at: idx)
            if activeByWorktree[worktreeId] == sessionId {
                if order.isEmpty {
                    activeByWorktree.removeValue(forKey: worktreeId)
                } else {
                    let nextIdx = min(idx, order.count - 1)
                    activeByWorktree[worktreeId] = order[nextIdx]
                }
            }
        }
        if order.isEmpty {
            orderByWorktree.removeValue(forKey: worktreeId)
        } else {
            orderByWorktree[worktreeId] = order
        }
        if let idx = removedIndex {
            store?.removeTabSpec(worktreeId: worktreeId, at: idx)
        }
    }

    /// Terminate every tab in a worktree. Used when a worktree is deleted
    /// or untracked.
    func terminate(worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        let ids = orderByWorktree[worktreeId] ?? []
        for sid in ids {
            terminate(sessionId: sid)
        }
    }

    /// Restart the active session in a worktree (used by the "Restart Session"
    /// placeholder button after a shell exits).
    func restartSession(for worktree: Worktree, setupCommands: [String]) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let sid = activeByWorktree[worktree.id] {
            terminate(sessionId: sid)
        }
        _ = startSession(for: worktree, setupCommands: setupCommands)
    }

    // MARK: - Font sizing

    /// ⌘+ — grow the terminal font one step (clamped to `maxFontSize`).
    func increaseFontSize() {
        applyFontSize(Self.steppedFontSize(from: terminalFontSize, delta: Self.fontSizeStep))
    }

    /// ⌘- — shrink the terminal font one step (clamped to `minFontSize`).
    func decreaseFontSize() {
        applyFontSize(Self.steppedFontSize(from: terminalFontSize, delta: -Self.fontSizeStep))
    }

    /// ⌘0 — restore the default terminal font size.
    func resetFontSize() {
        applyFontSize(Self.defaultFontSize)
    }

    /// Apply `size` (clamped) to every live `TerminalView` and persist it.
    /// No-op when the size is unchanged so a key-repeat at a bound is cheap.
    private func applyFontSize(_ size: CGFloat) {
        dispatchPrecondition(condition: .onQueue(.main))
        let clamped = Self.clampedFontSize(size)
        guard clamped != terminalFontSize else { return }
        terminalFontSize = clamped
        let font = Self.terminalFont(size: clamped)
        for entry in sessionsById.values {
            entry.terminalView.font = font
        }
        UserDefaults.standard.set(Double(clamped), forKey: Self.fontSizeDefaultsKey)
    }

    // MARK: - Private

    private func markExited(sessionId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        // KNOWN LIMITATION: PTY's onEOF callback does not currently carry the
        // child's exit status. We mark all exits as code 0. To distinguish
        // clean exit from crash, PTY would need to call waitpid and forward
        // the WEXITSTATUS to onEOF.
        guard let e = sessionsById[sessionId] else { return }
        AppLogger.session.info("exited session=\(sessionId, privacy: .public) pid=\(e.pty.pid)")
        e.session.state = .exited(code: 0)

        let tabIndex = (orderByWorktree[e.session.worktreeId] ?? [])
            .firstIndex(of: sessionId)
            .map { $0 + 1 } ?? 1
        Notifications.sessionEnded(
            worktreeName: e.worktreeDisplayName,
            branch: e.worktreeBranch,
            tabLabel: "shell \(tabIndex)"
        )
    }

    private func flushSetupCommands(sessionId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let e = sessionsById[sessionId] else { return }
        for cmd in e.pendingSetupCommands {
            let line = cmd + "\n"
            if let data = line.data(using: .utf8) {
                e.pty.write(data)
            }
        }
        e.pendingSetupCommands = []
    }

    /// Best installed terminal font family at `size`. Prefers Nerd Fonts so
    /// popular prompts (powerlevel10k, starship) render correctly. Falls back
    /// to the user's likely iTerm font (D2Coding) and finally Menlo.
    static func terminalFont(size: CGFloat) -> NSFont {
        let candidates = [
            "MesloLGS Nerd Font Mono",
            "MesloLGS Nerd Font",
            "MesloLGS NF",
            "JetBrainsMono Nerd Font Mono",
            "JetBrainsMonoNL Nerd Font Mono",
            "Hack Nerd Font Mono",
            "FiraCode Nerd Font Mono",
            "D2CodingLigature Nerd Font",
            "D2Coding",
            "Menlo",
        ]
        for name in candidates {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Default-size terminal font. Kept for callers that don't track size.
    static var preferredTerminalFont: NSFont { terminalFont(size: defaultFontSize) }
}

final class SessionTerminalDelegate: NSObject, TerminalViewDelegate {
    let pty: PTY
    init(pty: PTY) { self.pty = pty }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        pty.write(Data(data))
    }
    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0, newRows > 0 else { return }
        pty.resize(cols: Int32(newCols), rows: Int32(newRows))
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
