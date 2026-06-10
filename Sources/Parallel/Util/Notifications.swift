import Foundation
import UserNotifications

enum Notifications {
    /// `UNUserNotificationCenter.current()` requires the process to have a
    /// main bundle with a CFBundleIdentifier — true when running from a
    /// `.app`, but not when launched as a SwiftPM bare executable via
    /// `swift run`. Calling it without a bundle raises an Obj-C exception
    /// that Swift can't catch, so we check first and silently disable
    /// notifications in that environment.
    private static var isInBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Ask once for permission to post notifications. Safe to call repeatedly.
    /// No-op when not running inside an .app bundle.
    static func requestPermission() {
        guard isInBundle else {
            AppLogger.app.info("notifications disabled (no bundle — run from a .app to enable)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.app.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            AppLogger.app.info("notification permission granted=\(granted)")
        }
    }

    /// Post a notification that a worktree's shell session exited.
    /// No-op when not running inside an .app bundle.
    static func sessionEnded(worktreeName: String, branch: String, tabLabel: String) {
        guard isInBundle else { return }
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
