import Foundation

/// Test-only affordances, all gated behind environment variables so production
/// launches are unaffected. `PARALLEL_E2E=1` enables e2e mode; the others tune it.
enum TestMode {
    static func isE2E(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        env["PARALLEL_E2E"] == "1"
    }

    /// Overrides WorkspaceStore's support directory so tests never touch the
    /// user's real ~/Library/Application Support/Parallel.
    static func supportDirectory(_ env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let path = env["PARALLEL_SUPPORT_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
