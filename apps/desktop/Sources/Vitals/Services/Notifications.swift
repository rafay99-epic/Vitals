import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter. All calls are no-ops when
/// running outside an app bundle (e.g. `--probe` or `swift run`), where the
/// notification center is unavailable.
@MainActor
final class NotificationManager {
    static let supported = Bundle.main.bundleIdentifier != nil

    private var requestedAuthorization = false

    func requestAuthorizationIfNeeded() {
        guard Self.supported, !requestedAuthorization else { return }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.notice(.app, "notification authorization request failed", error: error)
            } else if !granted {
                Log.notice(.app, "the user has not granted notification permission — alerts won't show")
            }
        }
    }

    func send(title: String, body: String, id: String) {
        guard Self.supported else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.notice(.app, "couldn't post notification \"\(id)\"", error: error) }
        }
    }
}
