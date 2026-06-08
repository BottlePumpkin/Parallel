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

    /// sessionId → entry. The single source of truth for live sessions.
    private var sessionsById: [UUID: SessionEntry] = [:]
    /// worktreeId → ordered list of sessionIds (tab order).
    private var orderByWorktree: [UUID: [UUID]] = [:]
    /// worktreeId → active sessionId in its tab strip.
    private var activeByWorktree: [UUID: UUID] = [:]

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

    /// Return active session for the worktree, or create the first tab.
    @discardableResult
    func ensureSession(for worktree: Worktree, setupCommands: [String] = []) -> SessionEntry? {
        dispatchPrecondition(condition: .onQueue(.main))
        if let e = activeSession(for: worktree.id) { return e }
        return startSession(for: worktree, setupCommands: setupCommands)
    }

    /// Start a new tab in the worktree's strip and make it active.
    @discardableResult
    func startSession(for worktree: Worktree, setupCommands: [String]) -> SessionEntry? {
        dispatchPrecondition(condition: .onQueue(.main))
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let pty = PTY(shell: shell, cwd: worktree.path) else {
            AppLogger.session.error("PTY fork failed for \(worktree.displayName, privacy: .public)")
            return nil
        }
        AppLogger.session.info("start \(worktree.displayName, privacy: .public) pid=\(pty.pid)")

        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.font = Self.preferredTerminalFont
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
        entry.readSource = pty.startReading(
            onData: { data in
                DispatchQueue.main.async {
                    let bytes = [UInt8](data)
                    view.feed(byteArray: ArraySlice(bytes))
                }
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
    }

    /// Mark a specific tab as the active one in its worktree.
    func setActive(sessionId: UUID, in worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let order = orderByWorktree[worktreeId], order.contains(sessionId) else { return }
        guard activeByWorktree[worktreeId] != sessionId else { return }
        activeByWorktree[worktreeId] = sessionId
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
        if let idx = order.firstIndex(of: sessionId) {
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

    /// Best installed font for the terminal. Prefers Nerd Fonts so popular
    /// prompts (powerlevel10k, starship) render correctly. Falls back to the
    /// user's likely iTerm font (D2Coding) and finally Menlo.
    static let preferredTerminalFont: NSFont = {
        let size: CGFloat = 13
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
    }()
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
