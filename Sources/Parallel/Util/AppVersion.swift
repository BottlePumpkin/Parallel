import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Read-only access to the current app + host environment, formatted for
/// issue templates. The pure `signature(...)` function is unit-tested; the
/// run-time accessors (`current`, `environmentSignature`) compose it with
/// real process state.
enum AppVersion {
    static let fallback = SemanticVersion("0.0.0")!

    static var current: SemanticVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw.flatMap(SemanticVersion.init) ?? fallback
    }

    static var environmentSignature: String {
        signature(
            version: current,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: machineArchitecture(),
            logDirectory: "~/Library/Logs/Parallel/"
        )
    }

    /// Pure formatter — testable.
    static func signature(version: SemanticVersion,
                          osVersion: String,
                          architecture: String,
                          logDirectory: String) -> String {
        """
        - Parallel: \(version.description)
        - macOS: \(osVersion)
        - Architecture: \(architecture)
        - Log: \(logDirectory)
        """
    }

    private static func machineArchitecture() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let chars: [CChar] = mirror.children.compactMap { $0.value as? CChar }
        let bytes = chars.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
