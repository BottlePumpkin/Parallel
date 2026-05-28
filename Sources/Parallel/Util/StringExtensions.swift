import Foundation

extension String {
    /// Split into non-empty, whitespace-trimmed lines. Used to convert a
    /// multiline TextField value into a setup-commands array.
    func nonEmptyLines() -> [String] {
        split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
