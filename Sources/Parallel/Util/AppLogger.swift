import Foundation
import os

/// Centralized `os.Logger` categories. Stream from Console.app by filtering
/// subsystem `com.byeonghopark.parallel`.
enum AppLogger {
    static let app      = Logger(subsystem: "com.byeonghopark.parallel", category: "app")
    static let store    = Logger(subsystem: "com.byeonghopark.parallel", category: "store")
    static let worktree = Logger(subsystem: "com.byeonghopark.parallel", category: "worktree")
    static let session  = Logger(subsystem: "com.byeonghopark.parallel", category: "session")
    static let status   = Logger(subsystem: "com.byeonghopark.parallel", category: "status")

    /// Ensures `~/Library/Logs/Parallel/` exists for future file logging.
    /// `os.Logger` already streams to Console.app automatically; we just
    /// guarantee the conventional file-logging directory is present.
    static func bootstrapFileLogging() {
        #if DEBUG
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Parallel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        app.info("Parallel started. Log dir: \(dir.path, privacy: .public)")
        #endif
    }
}
