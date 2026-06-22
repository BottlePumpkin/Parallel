import Foundation

/// Decides whether the currently-running app bundle can be replaced in place by
/// an in-app update. Pure (filesystem access is injected) so it is unit-tested.
enum UpdateInstallTarget: Equatable {
    /// The `.app` bundle URL to replace.
    case replaceable(URL)
    /// Update can't proceed; the String is a user-facing reason.
    case unsupported(String)

    static func resolve(
        bundleURL: URL,
        isWritable: (URL) -> Bool = { FileManager.default.isWritableFile(atPath: $0.path) }
    ) -> UpdateInstallTarget {
        guard bundleURL.pathExtension == "app" else {
            return .unsupported("Running from a development build — update via the install command instead.")
        }
        if bundleURL.path.contains("/AppTranslocation/") {
            return .unsupported("Move Parallel into /Applications first, then update.")
        }
        let parent = bundleURL.deletingLastPathComponent()
        guard isWritable(parent) else {
            return .unsupported("Can't write to \(parent.path) — install manually.")
        }
        return .replaceable(bundleURL)
    }
}
