import Foundation
import os
import Darwin

/// Centralized `os.Logger` categories. Stream from Console.app by filtering
/// subsystem `com.byeonghopark.parallel`. In DEBUG builds, stderr+stdout
/// (which is where SwiftTerm warnings and our own print fallbacks land)
/// is also mirrored to a timestamped file under `~/Library/Logs/Parallel/`.
enum AppLogger {
    static let app      = Logger(subsystem: "com.byeonghopark.parallel", category: "app")
    static let store    = Logger(subsystem: "com.byeonghopark.parallel", category: "store")
    static let worktree = Logger(subsystem: "com.byeonghopark.parallel", category: "worktree")
    static let session  = Logger(subsystem: "com.byeonghopark.parallel", category: "session")
    static let status   = Logger(subsystem: "com.byeonghopark.parallel", category: "status")
    static let terminalIO = Logger(subsystem: "com.byeonghopark.parallel", category: "terminalIO")

    static func bootstrapFileLogging() {
        #if DEBUG
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Parallel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = Self.timestamp()
        let logURL = dir.appendingPathComponent("parallel-\(stamp).log")
        Self.startStderrMirror(to: logURL)

        app.info("Parallel started — mirror log: \(logURL.path, privacy: .public)")
        #endif
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// Set up a pipe → background-read thread that fan-outs to both the
    /// original stderr (so console output still works) and the log file.
    private static func startStderrMirror(to file: URL) {
        // Open the log file for append.
        let fileFD = open(file.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fileFD >= 0 else {
            app.error("open() failed for log mirror: \(String(cString: strerror(errno)), privacy: .public)")
            return
        }

        // Set up two pipes, one for stderr and one for stdout.
        mirrorFD(STDERR_FILENO, into: fileFD)
        mirrorFD(STDOUT_FILENO, into: fileFD)
    }

    private static func mirrorFD(_ originalFD: Int32, into fileFD: Int32) {
        var pipefd: [Int32] = [-1, -1]
        guard pipe(&pipefd) == 0 else { return }
        let readEnd = pipefd[0]
        let writeEnd = pipefd[1]

        // Save the original fd so we can still write to the real console.
        let consoleFD = dup(originalFD)
        guard consoleFD >= 0 else {
            close(readEnd); close(writeEnd)
            return
        }
        // Replace original fd with the pipe write end so all writes flow in.
        guard dup2(writeEnd, originalFD) >= 0 else {
            close(readEnd); close(writeEnd); close(consoleFD)
            return
        }
        close(writeEnd) // process now writes via originalFD

        // Background reader: fan-out chunks to console and the file.
        DispatchQueue.global(qos: .utility).async {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(readEnd, &buffer, buffer.count)
                if n <= 0 { break }
                _ = Darwin.write(consoleFD, buffer, n)
                _ = Darwin.write(fileFD, buffer, n)
            }
            close(readEnd)
            close(consoleFD)
        }
    }
}
