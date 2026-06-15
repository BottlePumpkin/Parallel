import Foundation

/// Comparable version tag parser. Accepts "0.1.4", "v0.1.4". Strips any
/// `-prerelease` or `+build` suffix and parses the numeric core only —
/// pre-release ordering is out of scope for this app's release scheme.
struct SemanticVersion: Comparable, Equatable, CustomStringConvertible {
    let components: [Int]

    init?(_ raw: String) {
        let trimmed = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        let parts = core.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }
        var ints: [Int] = []
        for p in parts {
            guard let n = Int(p), n >= 0 else { return nil }
            ints.append(n)
        }
        self.components = ints
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = Swift.max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = Swift.max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return false }
        }
        return true
    }
}
