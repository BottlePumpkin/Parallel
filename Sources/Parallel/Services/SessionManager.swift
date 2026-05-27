import Foundation
import SwiftTerm
import Observation
import AppKit

@Observable
final class SessionManager {

    /// worktreeId → session entry
    private var sessions: [UUID: SessionEntry] = [:]

    struct SessionEntry {
        let session: Session
        let pty: PTY
        let terminalView: TerminalView
        var readSource: DispatchSourceRead?
        var pendingSetupCommands: [String]
    }

    /// Get an existing session for the worktree, or start one.
    @discardableResult
    func ensureSession(for worktree: Worktree, setupCommands: [String] = []) -> SessionEntry? {
        if let e = sessions[worktree.id] { return e }
        return startSession(for: worktree, setupCommands: setupCommands)
    }

    /// Always start a fresh session, replacing any existing one.
    @discardableResult
    func startSession(for worktree: Worktree, setupCommands: [String]) -> SessionEntry? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let pty = PTY(shell: shell, cwd: worktree.path) else { return nil }

        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let delegate = SessionTerminalDelegate(pty: pty)
        view.terminalDelegate = delegate

        var entry = SessionEntry(
            session: Session(worktreeId: worktree.id, pid: pty.pid),
            pty: pty,
            terminalView: view,
            readSource: nil,
            pendingSetupCommands: setupCommands
        )

        // Retain the delegate strongly (TerminalView holds it weakly).
        retainedDelegates[worktree.id] = delegate

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

        if !setupCommands.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.flushSetupCommands(worktreeId: worktree.id)
            }
        }

        return entry
    }

    func session(for worktreeId: UUID) -> SessionEntry? {
        sessions[worktreeId]
    }

    func terminate(worktreeId: UUID) {
        guard let entry = sessions[worktreeId] else { return }
        entry.pty.terminate()
        entry.readSource?.cancel()
        sessions.removeValue(forKey: worktreeId)
        retainedDelegates.removeValue(forKey: worktreeId)
    }

    func restartSession(for worktree: Worktree, setupCommands: [String]) {
        terminate(worktreeId: worktree.id)
        _ = startSession(for: worktree, setupCommands: setupCommands)
    }

    private func markExited(worktreeId: UUID) {
        guard let e = sessions[worktreeId] else { return }
        e.session.state = .exited(code: 0)
    }

    private func flushSetupCommands(worktreeId: UUID) {
        guard var e = sessions[worktreeId] else { return }
        for cmd in e.pendingSetupCommands {
            let line = cmd + "\n"
            if let data = line.data(using: .utf8) {
                e.pty.write(data)
            }
        }
        e.pendingSetupCommands = []
        sessions[worktreeId] = e
    }

    /// Strong refs to delegates (TerminalView holds them weakly).
    private var retainedDelegates: [UUID: SessionTerminalDelegate] = [:]
}

private final class SessionTerminalDelegate: NSObject, TerminalViewDelegate {
    let pty: PTY
    init(pty: PTY) { self.pty = pty }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        pty.write(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}

    func setTerminalTitle(source: TerminalView, title: String) {}

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        pty.resize(cols: Int32(newCols), rows: Int32(newRows))
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func bell(source: TerminalView) {}

    func clipboardCopy(source: TerminalView, content: Data) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
