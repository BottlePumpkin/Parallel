import Foundation
import Darwin

/// posix forkpty wrapper.
/// Forks a child process for a shell, and exposes the master fd for I/O.
final class PTY {

    let pid: pid_t
    let masterFD: Int32

    /// Fork a shell process attached to a pseudo-terminal.
    /// - Parameters:
    ///   - shell: absolute path to executable. Typically `$SHELL` or `/bin/zsh`.
    ///   - args: arguments after the executable (default: empty — interactive shell).
    ///   - cwd: working directory for the child.
    ///   - env: environment variables for the child (defaults to inheriting the parent).
    ///   - cols/rows: initial terminal size.
    /// - Returns: nil if `forkpty` fails.
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
            chdir(cwd.path)
            var mergedEnv = env
            if mergedEnv["TERM"] == nil { mergedEnv["TERM"] = "xterm-256color" }
            let cEnv: [UnsafeMutablePointer<CChar>?] =
                mergedEnv.map { strdup("\($0.key)=\($0.value)") } + [nil]
            let cArgs: [UnsafeMutablePointer<CChar>?] =
                ([shell] + args).map { strdup($0) } + [nil]
            execve(shell, cArgs, cEnv)
            // exec failed
            _exit(127)
        }

        self.pid = pid
        self.masterFD = master
    }

    /// Write bytes to the child's stdin.
    func write(_ data: Data) {
        data.withUnsafeBytes { _ = Darwin.write(masterFD, $0.baseAddress, data.count) }
    }

    /// Resize the child's terminal.
    func resize(cols: Int32, rows: Int32) {
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = withUnsafeMutablePointer(to: &size) { ioctl(masterFD, TIOCSWINSZ, $0) }
    }

    /// Start async reads from the master fd. Calls `onData` for each chunk and
    /// `onEOF` once when the child closes. Returns a DispatchSourceRead that the
    /// caller must retain (it's cancelled on EOF too).
    func startReading(onData: @escaping (Data) -> Void,
                      onEOF: @escaping () -> Void) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler {
            let avail = Int(source.data)
            guard avail > 0 else { return }
            var buf = [UInt8](repeating: 0, count: avail)
            let n = read(self.masterFD, &buf, avail)
            if n > 0 {
                onData(Data(buf.prefix(n)))
            } else if n == 0 {
                onEOF()
                source.cancel()
            }
        }
        source.resume()
        return source
    }

    /// Send SIGTERM, then SIGKILL after 2 seconds if the child is still alive.
    func terminate() {
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [pid] in
            kill(pid, SIGKILL)
        }
    }
}
