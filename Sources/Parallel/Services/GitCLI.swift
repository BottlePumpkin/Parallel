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
    /// Exit code ≠ 0 is returned normally (caller decides what to do).
    /// Throws GitError only if the process couldn't be launched.
    static func run(_ args: [String], in cwd: URL, timeout: TimeInterval = 30) throws -> Result {
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

        proc.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return Result(
            exitCode: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
