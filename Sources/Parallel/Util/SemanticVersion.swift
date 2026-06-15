import Foundation

/// Comparable version tag parser. Accepts "0.1.4", "v0.1.4". Strips any
/// `-prerelease` or `+build` suffix and parses the numeric core only —
/// pre-release ordering is out of scope for this app's release scheme.
struct SemanticVersion: Comparable, Hashable, CustomStringConvertible {
    let components: [Int]

    init?(_ raw: String) {
        let trimmed = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        // `split(separator:)` with `omittingEmptySubsequences: false` keeps "" so
        // we reject malformed tags like "1..2" or "1.2." instead of silently
        // dropping the empty field.
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return nil }
        var ints: [Int] = []
        for p in parts {
            guard !p.isEmpty, let n = Int(p), n >= 0 else { return nil }
            ints.append(n)
        }
        self.components = ints
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    /// Pad both component arrays to the same length with zeros and compare.
    /// "1.2" and "1.2.0" must be equal, so they must also hash equal.
    private static func padded(_ a: [Int], to length: Int) -> [Int] {
        a.count >= length ? a : a + Array(repeating: 0, count: length - a.count)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let length = Swift.max(lhs.components.count, rhs.components.count)
        let l = padded(lhs.components, to: length)
        let r = padded(rhs.components, to: length)
        for i in 0..<length {
            if l[i] != r[i] { return l[i] < r[i] }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let length = Swift.max(lhs.components.count, rhs.components.count)
        return padded(lhs.components, to: length) == padded(rhs.components, to: length)
    }

    func hash(into hasher: inout Hasher) {
        // Trim trailing zeros so "1.2" and "1.2.0" hash identically.
        var trimmed = components
        while trimmed.count > 1, trimmed.last == 0 {
            trimmed.removeLast()
        }
        hasher.combine(trimmed)
    }
}
