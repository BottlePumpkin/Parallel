import Foundation

extension UserDefaults {
    private enum UpdateKeys {
        static let lastCheckAt = "parallel.updateCheck.lastAt"
        static let skippedVersion = "parallel.updateCheck.skippedVersion"
    }

    var lastUpdateCheckAt: Date? {
        get { object(forKey: UpdateKeys.lastCheckAt) as? Date }
        set { set(newValue, forKey: UpdateKeys.lastCheckAt) }
    }

    var skippedUpdateVersion: String? {
        get { string(forKey: UpdateKeys.skippedVersion) }
        set { set(newValue, forKey: UpdateKeys.skippedVersion) }
    }
}
