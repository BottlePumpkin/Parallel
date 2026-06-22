import Foundation
import AppKit
import Observation

enum UpdaterError: Error {
    case message(String)
    var text: String {
        if case .message(let m) = self { return m }
        return "Update failed."
    }
}

/// Downloads a release zip, verifies it, atomically replaces the running bundle
/// in place, and relaunches. The pure `bundleShortVersion` helper is unit-tested;
/// the side-effecting pipeline (network, ditto, file swap, relaunch) is verified
/// manually, like SessionManager.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double)
        case unpacking
        case verifying
        case installing
        case relaunching
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    /// Reads `CFBundleShortVersionString` from a `.app` bundle URL. Pure.
    nonisolated static func bundleShortVersion(at bundleURL: URL) -> String? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    /// Kicks off the update pipeline (implemented in Task 4).
    func update(from info: UpdateInfo, target: URL, session: URLSession = .shared) {
        // Implemented in Task 4.
        phase = .failed("Updater not yet implemented.")
    }
}
