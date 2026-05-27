import Foundation

extension Date {
    /// Truncates to whole-second precision so default ISO8601 round-trips exactly.
    /// Sub-second precision has no semantic value for the timestamps we persist.
    var truncatedToSeconds: Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded(.towardZero))
    }
}
