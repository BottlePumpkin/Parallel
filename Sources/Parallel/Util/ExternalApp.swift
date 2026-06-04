import Foundation
import AppKit

/// External apps the user can open a worktree path in. Installation is
/// detected by checking the canonical `/Applications/*.app` path. Users
/// with non-standard install locations won't see the entry — acceptable
/// trade-off for not requiring an LaunchServices lookup.
enum ExternalApp: CaseIterable {
    case finder
    case cursor
    case vscode
    case androidStudio
    case intellij
    case xcode

    var displayName: String {
        switch self {
        case .finder:        return "Finder"
        case .cursor:        return "Cursor"
        case .vscode:        return "Visual Studio Code"
        case .androidStudio: return "Android Studio"
        case .intellij:      return "IntelliJ IDEA"
        case .xcode:         return "Xcode"
        }
    }

    /// SF Symbol used in the menu next to the name.
    var iconSystemName: String {
        switch self {
        case .finder: return "folder"
        default:      return "app"
        }
    }

    private var bundlePath: String? {
        switch self {
        case .finder:        return nil
        case .cursor:        return "/Applications/Cursor.app"
        case .vscode:        return "/Applications/Visual Studio Code.app"
        case .androidStudio: return "/Applications/Android Studio.app"
        case .intellij:      return "/Applications/IntelliJ IDEA.app"
        case .xcode:         return "/Applications/Xcode.app"
        }
    }

    var isInstalled: Bool {
        if self == .finder { return true }
        guard let p = bundlePath else { return false }
        return FileManager.default.fileExists(atPath: p)
    }

    func open(at path: URL) {
        if self == .finder {
            NSWorkspace.shared.open(path)
            return
        }
        guard let bp = bundlePath else { return }
        let appURL = URL(fileURLWithPath: bp)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([path], withApplicationAt: appURL, configuration: config) { _, error in
            if let error {
                AppLogger.app.error("open in \(self.displayName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
