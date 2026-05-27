import Foundation

enum PathSanitizer {
    /// Convert an arbitrary string (typically a git branch name) into a
    /// directory-safe name.
    ///
    /// Rules:
    /// - Allowed chars: `[A-Za-z0-9-_.]` (passed through verbatim)
    /// - All other chars (including slashes, whitespace, unicode/emoji) → `-`
    /// - Consecutive `-` collapsed to a single `-`
    /// - Leading and trailing `-` trimmed
    ///
    /// Contract: If the input is empty, or contains only non-allowed characters,
    /// the result is `""`. Callers must guard against empty output before using
    /// it as a path component.
    static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let replaced = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let joined = String(replaced)
        let collapsed = joined.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
