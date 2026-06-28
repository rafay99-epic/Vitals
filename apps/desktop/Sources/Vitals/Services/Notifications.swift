import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter. All calls are no-ops when
/// running outside an app bundle (e.g. `--probe` or `swift run`), where the
/// notification center is unavailable.
///
/// It also acts as the notification *delegate* so update notifications can carry
/// action buttons ("Download & Install", "Install & Relaunch") that work while
/// the app has no window open: tapping a button — or the banner itself — routes
/// back to the `Updater` through `onUpdateAction`, which kicks off the
/// download/install in the background.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let supported = Bundle.main.bundleIdentifier != nil

    /// Categories + action identifiers wired to the update flow. The category id
    /// goes on the `UNNotificationContent`; the action id comes back in
    /// `didReceive`. Tapping the banner body delivers the system *default* action,
    /// which we treat as the category's primary action.
    enum Category {
        static let updateAvailable = "vitals.update.available"
        static let updateReady = "vitals.update.ready"
    }
    enum Action {
        static let download = "vitals.update.download"
        static let install = "vitals.update.install"
        static let later = "vitals.update.later"
    }

    /// What the user asked the updater to do from a notification.
    enum UpdateAction { case download, install }

    /// Set by the `Updater`. Invoked on the main actor when the user taps an
    /// update notification (button or banner body).
    var onUpdateAction: ((UpdateAction) -> Void)?

    private var requestedAuthorization = false

    override init() {
        super.init()
        guard Self.supported else { return }
        // Register the delegate + categories at launch — before authorization and
        // regardless of the auto-update toggle — so a tap on a notification that
        // was delivered while the app was closed is handled on the next launch.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerUpdateCategories(on: center)
    }

    private func registerUpdateCategories(on center: UNUserNotificationCenter) {
        let download = UNNotificationAction(
            identifier: Action.download, title: "Download & Install", options: [.foreground]
        )
        let install = UNNotificationAction(
            identifier: Action.install, title: "Install & Relaunch", options: [.foreground]
        )
        let later = UNNotificationAction(identifier: Action.later, title: "Later", options: [])
        let available = UNNotificationCategory(
            identifier: Category.updateAvailable, actions: [download, later],
            intentIdentifiers: [], options: []
        )
        let ready = UNNotificationCategory(
            identifier: Category.updateReady, actions: [install, later],
            intentIdentifiers: [], options: []
        )
        center.setNotificationCategories([available, ready])
    }

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

    /// Posts a notification. Pass `categoryId` (one of `Category`) to attach the
    /// update action buttons; omit it for plain informational alerts.
    func send(title: String, body: String, id: String, categoryId: String? = nil) {
        guard Self.supported else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryId { content.categoryIdentifier = categoryId }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.notice(.app, "couldn't post notification \"\(id)\"", error: error) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show update/alert banners even when Vitals is the frontmost app — without
    /// this, foreground notifications are silently suppressed by the system.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Route a tapped update notification back to the updater. The banner body
    /// (default action) does the same thing as the category's primary button;
    /// "Later" and any other action just dismiss.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        let resolved: UpdateAction?
        switch action {
        case Action.download:
            resolved = .download
        case Action.install:
            resolved = .install
        case UNNotificationDefaultActionIdentifier:
            // Tapping the banner body → the category's primary action, but ONLY
            // for the update categories. An overheat/thermal/custom-alert tap
            // (no category, or a non-update one) must never start an update.
            switch category {
            case Category.updateReady:     resolved = .install
            case Category.updateAvailable: resolved = .download
            default:                       resolved = nil
            }
        default:
            resolved = nil  // "Later", dismiss, or an unrelated category
        }
        if let resolved {
            Task { @MainActor in self.onUpdateAction?(resolved) }
        }
        completionHandler()
    }
}
