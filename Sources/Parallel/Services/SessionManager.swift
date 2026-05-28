import Foundation
import SwiftTerm
import Observation
import AppKit

/// Owns one PTY + TerminalView per worktree.
///
/// Thread contract: all mutating methods (`ensureSession`, `startSession`,
/// `terminate`, `restartSession`) MUST be called on the main thread. Callbacks
/// from the underlying PTY's background read pump are routed back to main
/// before any state mutation.
@Observable
final class SessionManager {

    /// worktreeId → entry
    private var sessions: [UUID: SessionEntry] = [:]

    /// `SessionEntry` is a class so the delegate, pty, and view share one
    /// lifetime and we don't need a parallel retain dict. SwiftTerm's
    /// `TerminalView` holds the delegate weakly, so the strong reference
    /// must live somewhere — here.
    final class SessionEntry {
        let session: Session
        let pty: PTY
        let terminalView: TerminalView
        var readSource: DispatchSourceRead?
        var pendingSetupCommands: [String]
        let delegate: SessionTerminalDelegate

        init(session: Session, pty: PTY, terminalView: TerminalView,
             readSource: DispatchSourceRead?, pendingSetupCommands: [String],
             delegate: SessionTerminalDelegate) {
            self.session = session
            self.pty = pty
            self.terminalView = terminalView
            self.readSource = readSource
            self.pendingSetupCommands = pendingSetupCommands
            self.delegate = delegate
        }
    }

    /// Return existing session for the worktree, or start a new one.
    @discardableResult
    func ensureSession(for worktree: Worktree, setupCommands: [String] = []) -> SessionEntry? {
        dispatchPrecondition(condition: .onQueue(.main))
        if let e = sessions[worktree.id] { return e }
        return startSession(for: worktree, setupCommands: setupCommands)
    }

    /// Always start a fresh session, replacing any existing one.
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

        let entry = SessionEntry(
            session: Session(worktreeId: worktree.id, pid: pty.pid),
            pty: pty,
            terminalView: view,
            readSource: nil,
            pendingSetupCommands: setupCommands,
            delegate: delegate
        )

        entry.readSource = pty.startReading(
            onData: { data in
                DispatchQueue.main.async {
                    let bytes = [UInt8](data)
                    view.feed(byteArray: ArraySlice(bytes))
                }
            },
            onEOF: { [weak self] in
                DispatchQueue.main.async {
                    self?.markExited(worktreeId: worktree.id)
                }
            }
        )

        sessions[worktree.id] = entry

        // KNOWN LIMITATION: setup commands are flushed after a fixed 500ms
        // delay. If the shell takes longer to initialize (slow disk, network
        // home, etc.) the commands fire before the shell is ready and are
        // dropped silently. A future version should detect first-prompt or
        // use a synchronization marker. (spec §7 PTY Integration)
        if !setupCommands.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.flushSetupCommands(worktreeId: worktree.id)
            }
        }

        return entry
    }

    /// Read-only lookup. Safe to call from any thread (dict reads are
    /// guarded by the main-thread mutation contract — readers from non-main
    /// can see a slightly stale value but not crash).
    func session(for worktreeId: UUID) -> SessionEntry? {
        sessions[worktreeId]
    }

    /// All currently-running sessions. Used by TerminalPaneView to keep
    /// every session's SwiftTerm view mounted continuously, with only
    /// the active worktree's view made visible. Re-mounting the same
    /// NSView across worktree switches corrupted SwiftTerm's internal
    /// scroll/layout cache; this avoids it.
    var allRunningSessions: [SessionEntry] {
        sessions.values.filter {
            if case .running = $0.session.state { return true }
            return false
        }
    }

    func terminate(worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let entry = sessions[worktreeId] else { return }
        AppLogger.session.info("terminate worktreeId=\(worktreeId, privacy: .public) pid=\(entry.pty.pid)")
        entry.pty.terminate()
        entry.readSource?.cancel()
        sessions.removeValue(forKey: worktreeId)
    }

    func restartSession(for worktree: Worktree, setupCommands: [String]) {
        dispatchPrecondition(condition: .onQueue(.main))
        terminate(worktreeId: worktree.id)
        _ = startSession(for: worktree, setupCommands: setupCommands)
    }

    private func markExited(worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        // KNOWN LIMITATION: PTY's onEOF callback does not currently carry the
        // child's exit status. We mark all exits as code 0. To distinguish
        // clean exit from crash, PTY would need to call waitpid and forward
        // the WEXITSTATUS to onEOF. (v2)
        guard let e = sessions[worktreeId] else { return }
        AppLogger.session.info("exited worktreeId=\(worktreeId, privacy: .public) pid=\(e.pty.pid)")
        e.session.state = .exited(code: 0)
    }

    private func flushSetupCommands(worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let e = sessions[worktreeId] else { return }
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
    /// Picked once at first access and cached.
    static let preferredTerminalFont: NSFont = {
        let size: CGFloat = 13
        let candidates = [
            "MesloLGS Nerd Font Mono",   // v3 cask (font-meslo-lg-nerd-font)
            "MesloLGS Nerd Font",
            "MesloLGS NF",               // legacy v2 name
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
        // SwiftTerm reports cols=-1, rows=0 during the initial layout pass when
        // the NSView's frame is still 0×0. Guard before forwarding to PTY.
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
