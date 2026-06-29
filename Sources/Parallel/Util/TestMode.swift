import Foundation

/// Test-only affordances, all gated behind environment variables so production
/// launches are unaffected. `PARALLEL_E2E=1` enables e2e mode; the others tune it.
enum TestMode {
    static func isE2E(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        env["PARALLEL_E2E"] == "1"
    }

    /// Puts new terminals into any-event SGR mouse tracking at startup (as Claude
    /// would) so UI tests can exercise the wheel/hover/drag behavior without a
    /// real mouse-mode program. Also turns on outgoing mouse-report capture.
    static func isE2EMouse(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        env["PARALLEL_E2E_MOUSE"] == "1"
    }

    /// Overrides WorkspaceStore's support directory so tests never touch the
    /// user's real ~/Library/Application Support/Parallel.
    static func supportDirectory(_ env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let path = env["PARALLEL_SUPPORT_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
