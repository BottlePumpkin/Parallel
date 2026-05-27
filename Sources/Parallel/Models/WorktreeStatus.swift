import Foundation

struct WorktreeStatus: Equatable {
    var isDirty: Bool = false
    var changedFiles: Int = 0
    var ahead: Int = 0
    var behind: Int = 0
    var lastCheckedAt: Date? = nil
    var lastError: String? = nil
}
