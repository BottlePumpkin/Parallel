import Foundation

/// Persisted metadata for a single shell tab inside a worktree.
/// Used to restore the same number (and labels) of tabs after an app
/// restart. PTYs themselves don't persist — only this spec list.
struct TabSpec: Codable, Equatable, Hashable {
    var label: String?
}
