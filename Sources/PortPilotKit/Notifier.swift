import Foundation
import UserNotifications

/// Notifications only work from a real app bundle; when Port Pilot is run
/// straight from `swift run` these calls are skipped instead of crashing.
enum Notifier {
    private static var authorized = false

    static var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            authorized = granted
        }
    }

    static func post(title: String, body: String) {
        guard available, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
