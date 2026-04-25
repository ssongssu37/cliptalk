import Foundation
import UserNotifications

/// Tiny UNUserNotificationCenter wrapper for the Services flow (download +
/// quick-capture share this kind of "you triggered something from another
/// app, here's the result" surface). Mirrors what QuickClipper does inline.
enum ServiceNotifications {

    static func post(title: String, body: String, isError: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                    deliver(title: title, body: body, isError: isError)
                }
            } else {
                deliver(title: title, body: body, isError: isError)
            }
        }
    }

    private static func deliver(title: String, body: String, isError: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isError ? .defaultCritical : .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
