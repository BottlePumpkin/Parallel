import Foundation

enum GitCLI {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    enum GitError: Error, CustomStringConvertible {
        case launchFailed(String)
        var description: String {
            switch self {
            case .launchFailed(let m): return "git launch failed: \(m)"
            }
        }
    }

    /// Run `git <args>` synchronously in `cwd`. Returns exitCode/stdout/stderr.
    /// - Exit code ≠ 0 is returned normally; callers decide what to do.
    /// - Throws `GitError.launchFailed` only when the process can't start.
    /// - stdout/stderr are decoded as UTF-8; non-UTF-8 bytes fall back to
    ///   ISO Latin-1 so callers always get back the byte content as a string.
    /// - Pipes are drained on background queues to avoid the classic POSIX
    ///   deadlock when output exceeds the kernel pipe buffer (~64KB on macOS).
    static func run(_ args: [String], in cwd: URL) throws -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git"] + args
        proc.currentDirectoryURL = cwd

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            throw GitError.launchFailed("\(error)")
        }

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        // Wait for the drain tasks first — they only return when the child
        // closes its pipes, which only happens on exit. Calling waitUntilExit
        // before the drains have started reading could deadlock if the child
        // fills its pipe buffer before the drains schedule on a worker thread.
        group.wait()
        proc.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8)
            ?? String(data: outData, encoding: .isoLatin1)
            ?? ""
        let stderr = String(data: errData, encoding: .utf8)
            ?? String(data: errData, encoding: .isoLatin1)
            ?? ""

        return Result(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
