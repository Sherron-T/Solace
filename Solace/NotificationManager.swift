import Foundation
import UserNotifications

/// Lets reminder banners show even while Solace is in the foreground.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// Set by RootView; tapping any Solace reminder lands here (opens the check-in).
    var onTap: (() -> Void)?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.onTap?() }
        completionHandler()
    }
}

/// One gentle local reminder a day — never a guilt trip, never streak-shaming.
/// Enabled from the caregiver dashboard; scheduling is real (UNUserNotificationCenter).
enum GentleReminder {
    private static let dailyID = "solace.gentle.daily"
    private static let previewID = "solace.gentle.preview"
    private static let demoID = "solace.gentle.demo"

    private static var dailyContent: UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "One small thing?"
        content.body = "There’s no rush, something gentle is waiting when you’re ready."
        content.sound = .default
        return content
    }

    /// Request permission and schedule the daily reminder (10:00). Also fires a
    /// one-time preview a few seconds out so the caregiver sees what it looks like.
    static func enable() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = dailyContent

            // Daily at 10:00
            var comps = DateComponents()
            comps.hour = 10
            comps.minute = 0
            let daily = UNNotificationRequest(
                identifier: dailyID,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            )
            center.add(daily)

            // 5-second preview so enabling shows something immediately
            let preview = UNMutableNotificationContent()
            preview.title = content.title
            preview.body = "This is how the daily reminder will look."
            preview.sound = .default
            center.add(UNNotificationRequest(
                identifier: previewID,
                content: preview,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            ))
        }
    }

    static func disable() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyID, previewID, demoID])
    }

    /// Demo hook: fires the real daily reminder a few seconds out, so a screen
    /// recording can capture the banner (and the tap into the check-in) without
    /// waiting for 10:00.
    static func fireDemo(in seconds: TimeInterval = 5) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(
                identifier: demoID,
                content: dailyContent,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            ))
        }
    }
}
