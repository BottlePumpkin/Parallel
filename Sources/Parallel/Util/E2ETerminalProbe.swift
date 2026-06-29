import Foundation

/// E2E-only capture of the mouse/control reports the terminal forwards to the
/// program, so a UI test can assert what a real gesture produced. Inert unless
/// `PARALLEL_E2E_MOUSE` is set. Reuses TerminalIODebug's privacy-safe extractor,
/// so only control reports (coordinates) are ever recorded — never keystrokes.
enum E2ETerminalProbe {
    static let enabled = TestMode.isE2EMouse()

    private static let lock = NSLock()
    private static var buffer: [String] = []

    static func record(_ bytes: [UInt8]) {
        guard enabled, let desc = TerminalIODebug.controlReportDescription(from: bytes) else { return }
        lock.lock(); defer { lock.unlock() }
        buffer.append(desc)
        if buffer.count > 200 { buffer.removeFirst(buffer.count - 200) }
    }

    /// Newline-joined recent reports, for the e2e probe to surface.
    static var reports: String {
        lock.lock(); defer { lock.unlock() }
        return buffer.joined(separator: "\n")
    }
}
