import Foundation
import UserNotifications

/// Pure banner-suppression policy (issue #12), unit-testable without AppKit.
enum NotificationBanner {
    /// Show a banner unless the belling session is visible and the app is active.
    static func shouldBanner(appActive: Bool, sessionVisible: Bool) -> Bool {
        !(appActive && sessionVisible)
    }
}

enum Notifications {
    /// `UNUserNotificationCenter.current()` raises an uncatchable Obj-C exception
    /// unless the process is a real `.app` bundle — true for the shipped app, but
    /// NOT for a SwiftPM bare executable (`swift run`) nor the xctest runner
    /// (whose bundle id is non-nil but whose bundle is not an `.app`). Require the
    /// `.app` extension so notifications silently no-op in both non-app contexts.
    private static var isInBundle: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

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

    /// A session finished its turn and is waiting for input.
    static func sessionNeedsAttention(worktreeId: UUID, sessionId: UUID,
                                      worktreeName: String, branch: String, tabLabel: String) {
        post(title: "Waiting for you", worktreeId: worktreeId, sessionId: sessionId,
             worktreeName: worktreeName, branch: branch, tabLabel: tabLabel)
    }

    /// A shell session exited on its own.
    static func sessionEnded(worktreeId: UUID, sessionId: UUID,
                             worktreeName: String, branch: String, tabLabel: String) {
        post(title: "Session ended", worktreeId: worktreeId, sessionId: sessionId,
             worktreeName: worktreeName, branch: branch, tabLabel: tabLabel)
    }

    private static func post(title: String, worktreeId: UUID, sessionId: UUID,
                             worktreeName: String, branch: String, tabLabel: String) {
        guard isInBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = worktreeName
        content.body = "\(tabLabel) · \(branch)"
        content.sound = .default
        content.userInfo = ["worktreeId": worktreeId.uuidString, "sessionId": sessionId.uuidString]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error {
                AppLogger.app.error("notify post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Routes banner interactions back into the app (issue #12): shows banners even
/// while the app is frontmost (we already decided to post), and on click sets the
/// store's navigation target so ContentView jumps to that session.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var store: NotificationStore?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let w = info["worktreeId"] as? String, let wid = UUID(uuidString: w),
           let s = info["sessionId"] as? String, let sid = UUID(uuidString: s) {
            Task { @MainActor in
                self.store?.navigationTarget = NavigationTarget(worktreeId: wid, sessionId: sid)
            }
        }
        completionHandler()
    }
}
