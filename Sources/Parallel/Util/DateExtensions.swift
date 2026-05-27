import Foundation

extension Date {
    /// Truncates to millisecond precision so ISO8601 (3 decimal places) round-trips exactly.
    var truncatedToMilliseconds: Date {
        let ms = (timeIntervalSinceReferenceDate * 1000).rounded(.towardZero) / 1000
        return Date(timeIntervalSinceReferenceDate: ms)
    }
}
