import Foundation

/// Opt-in, privacy-scoped debug logging for terminal I/O.
///
/// Disabled unless `PARALLEL_DEBUG_TERMINAL_IO` is set, so normal users incur
/// nothing. When on, it logs only SGR mouse/control reports the terminal sends
/// to the program (`ESC [ < Cb ; x ; y …` — coordinates, not content). Keystrokes
/// and pasted text never produce a description, so they are never logged. Output
/// goes to the local unified log (Console.app / `log stream`), never off-device.
///
/// This is the formalized, safe version of the throwaway instrumentation used to
/// diagnose the Claude hover-highlight (bare motion mis-encoded as a left-drag).
enum TerminalIODebug {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PARALLEL_DEBUG_TERMINAL_IO"] != nil
    }

    /// A loggable description of an outgoing SGR mouse/control report, or nil for
    /// anything else (keystrokes, pasted content, cursor keys) — so non-control
    /// bytes are never logged.
    static func controlReportDescription(from bytes: [UInt8]) -> String? {
        // Look for a contiguous CSI-private introducer: ESC [ <
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0x1b, bytes[i + 1] == 0x5b, bytes[i + 2] == 0x3c {
                return String(decoding: bytes[i...], as: UTF8.self)
                    .replacingOccurrences(of: "\u{1b}", with: "ESC")
            }
            i += 1
        }
        return nil
    }

    /// Log an outgoing data chunk if it is a control report and logging is on.
    static func logOutgoing(_ bytes: [UInt8]) {
        guard isEnabled, let desc = controlReportDescription(from: bytes) else { return }
        AppLogger.terminalIO.debug("→ \(desc, privacy: .public)")
    }
}
