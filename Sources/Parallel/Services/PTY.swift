import Foundation
import Darwin

/// posix forkpty wrapper. Forks a child process attached to a pseudo-terminal
/// and exposes the master fd for I/O.
///
/// Ownership contract:
/// - Caller owns the PTY instance. On deinit, the master fd is closed and any
///   active read source is cancelled.
/// - `terminate()` is safe to call multiple times.
final class PTY {

    let pid: pid_t
    let masterFD: Int32
    private var readSource: DispatchSourceRead?
    private var terminated = false

    /// - Parameters:
    ///   - shell: absolute path to the shell binary (e.g. `/bin/zsh`).
    ///   - args: extra args after the shell.
    ///   - cwd: working directory for the child.
    ///   - env: child environment.
    ///   - cols/rows: initial terminal size.
    ///
    /// argv[0] is set to `-<basename>` (e.g. `-zsh`) so the shell starts in
    /// LOGIN mode and sources the user's profile + rc files. Without this,
    /// PATH/aliases/tool-version managers are missing.
    init?(shell: String,
          args: [String] = [],
          cwd: URL,
          env: [String: String] = ProcessInfo.processInfo.environment,
          cols: Int32 = 120,
          rows: Int32 = 32) {
        var master: Int32 = 0
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)

        let pid = withUnsafeMutablePointer(to: &size) { sizePtr -> pid_t in
            forkpty(&master, nil, nil, sizePtr)
        }

        guard pid >= 0 else { return nil }

        if pid == 0 {
            // child process
            if chdir(cwd.path) != 0 {
                _exit(127)
            }
            var mergedEnv = env
            if mergedEnv["TERM"] == nil { mergedEnv["TERM"] = "xterm-256color" }
            let cEnv: [UnsafeMutablePointer<CChar>?] =
                mergedEnv.map { strdup("\($0.key)=\($0.value)") } + [nil]
            // Login-shell semantics: argv[0] = "-<basename>"
            let shellBase = (shell as NSString).lastPathComponent
            let loginName = "-" + shellBase
            let cArgs: [UnsafeMutablePointer<CChar>?] =
                ([loginName] + args).map { strdup($0) } + [nil]
            execve(shell, cArgs, cEnv)
            _exit(127)
        }

        self.pid = pid
        self.masterFD = master
    }

    deinit {
        readSource?.cancel()
        close(masterFD)
    }

    /// Write bytes to the child's stdin.
    func write(_ data: Data) {
        data.withUnsafeBytes { _ = Darwin.write(masterFD, $0.baseAddress, data.count) }
    }

    /// Resize the child's terminal.
    /// Ignores zero/negative dimensions — SwiftTerm emits these during the
    /// initial layout pass before its NSView has a real frame.
    func resize(cols: Int32, rows: Int32) {
        guard cols > 0, rows > 0 else { return }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = withUnsafeMutablePointer(to: &size) { ioctl(masterFD, TIOCSWINSZ, $0) }
    }

    /// Start async reads from the master fd.
    /// - `onData` is called for each chunk of bytes from the child.
    /// - `onEOF` is called once when the child closes the pty (clean exit OR
    ///   read error including `EIO` after process death on Darwin/BSD).
    /// The returned source is also retained internally and will be cancelled
    /// in deinit. The caller may still cancel it manually if they want to
    /// stop reading without releasing the PTY.
    @discardableResult
    func startReading(onData: @escaping (Data) -> Void,
                      onEOF: @escaping () -> Void) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [masterFD] in
            let avail = Int(source.data)
            guard avail > 0 else { return }
            var buf = [UInt8](repeating: 0, count: avail)
            let n = read(masterFD, &buf, avail)
            if n > 0 {
                onData(Data(buf.prefix(n)))
            } else if n == 0 {
                // clean EOF
                onEOF()
                source.cancel()
            } else {
                // n < 0: read error. On Darwin, EIO after child exits is normal.
                // EAGAIN/EINTR are transient; everything else means we're done.
                let err = errno
                if err != EAGAIN && err != EINTR {
                    onEOF()
                    source.cancel()
                }
            }
        }
        source.resume()
        readSource = source
        return source
    }

    /// Send SIGTERM. If the child is still alive after 2 seconds, send SIGKILL —
    /// but only after confirming via `waitpid(WNOHANG)` that the original child
    /// has not exited (which would have allowed the OS to recycle the pid).
    /// Safe to call multiple times.
    func terminate() {
        if terminated { return }
        terminated = true
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [pid] in
            var status: Int32 = 0
            let r = waitpid(pid, &status, WNOHANG)
            // r == 0  → child still alive AND still ours → safe to kill
            // r >  0  → child exited and we just reaped it → don't kill (pid may be recycled)
            // r == -1 → already reaped elsewhere or not our child → don't kill
            if r == 0 {
                kill(pid, SIGKILL)
                _ = waitpid(pid, &status, 0) // reap to avoid zombie
            }
        }
    }
}
