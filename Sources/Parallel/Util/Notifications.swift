import Foundation
import UserNotifications

enum Notifications {
    /// Ask once for permission to post notifications. Safe to call repeatedly
    /// — the system only prompts the first time, subsequent calls just
    /// resolve with the current authorization state.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.app.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            AppLogger.app.info("notification permission granted=\(granted)")
        }
    }

    /// Post a notification that a worktree's shell session exited.
    static func sessionEnded(worktreeName: String, branch: String, tabLabel: String) {
        let content = UNMutableNotificationContent()
        content.title = "Session ended"
        content.subtitle = worktreeName
        content.body = "\(tabLabel) · \(branch)"
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { error in
            if let error {
                AppLogger.app.error("notify post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
