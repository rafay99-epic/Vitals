import Foundation
import UserNotifications

/// Wrapper around UNUserNotificationCenter. No-ops outside an app bundle
/// (`--probe`, `swift run`), where the notification center is unavailable.
///
/// Also the notification delegate, so update action buttons work with no window
/// open: a tap routes to the `Updater` through `onUpdateAction`.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let supported = Bundle.main.bundleIdentifier != nil

    /// The category id goes on the content; the action id comes back in `didReceive`.
    enum Category {
        static let updateAvailable = "vitals.update.available"
        static let updateReady = "vitals.update.ready"
        static let remoteGrace = "vitals.remote.grace"
        static let remotePressure = "vitals.remote.pressure"
        static let remotePair = "vitals.remote.pair"
        static let shareGot = "vitals.share.got"
        static let shareAsk = "vitals.share.ask"
        static let shareWait = "vitals.share.wait"
    }
    enum Action {
        static let download = "vitals.update.download"
        static let install = "vitals.update.install"
        static let later = "vitals.update.later"
        static let cancelCommand = "vitals.remote.cancel"
        static let calmDown = "vitals.remote.calm"
        static let allowPair = "vitals.remote.pair.allow"
        static let denyPair = "vitals.remote.pair.deny"
        static let showDrop = "vitals.share.show"
        static let acceptDrop = "vitals.share.accept"
        static let declineDrop = "vitals.share.decline"
        static let cancelDrop = "vitals.share.cancel"
    }

    enum ShareAction: Equatable {
        case show(String)
        case decide(String, accept: Bool)
        case cancel(String)
    }

    nonisolated static func shareNotificationId(_ category: String, _ dropId: String) -> String { "\(category).\(dropId)" }

    enum RemoteAction: Equatable {
        case cancelCommand(String)
        case calmDown
        case resolvePair(id: String, allow: Bool)
    }

    /// Pair prompts post under this prefix so an Allow/Deny tap can recover the prompt id.
    nonisolated static func pairNotificationId(_ promptId: String) -> String { "vitals.remote.pair.\(promptId)" }

    static let shared = NotificationManager()

    var onRemoteAction: ((RemoteAction) -> Void)?
    var onShareAction: ((ShareAction) -> Void)?

    enum UpdateAction { case download, install }

    /// Set by the `Updater`. Called on the main actor.
    var onUpdateAction: ((UpdateAction) -> Void)?

    private var requestedAuthorization = false

    private override init() {
        super.init()
        guard Self.supported else { return }
        // Register at launch, before authorization and regardless of the
        // auto-update toggle, so a tap on a notification delivered while the
        // app was closed is still handled.
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
        let cancel = UNNotificationAction(identifier: Action.cancelCommand, title: "Cancel", options: [.destructive])
        let calm = UNNotificationAction(identifier: Action.calmDown, title: "Calm down", options: [])
        let grace = UNNotificationCategory(identifier: Category.remoteGrace, actions: [cancel], intentIdentifiers: [], options: [])
        let pressure = UNNotificationCategory(identifier: Category.remotePressure, actions: [calm], intentIdentifiers: [], options: [])
        let allowPair = UNNotificationAction(identifier: Action.allowPair, title: "Allow", options: [])
        let denyPair = UNNotificationAction(identifier: Action.denyPair, title: "Deny", options: [.destructive])
        let pair = UNNotificationCategory(identifier: Category.remotePair, actions: [allowPair, denyPair], intentIdentifiers: [], options: [])
        let show = UNNotificationAction(identifier: Action.showDrop, title: "Show in Finder", options: [.foreground])
        let accept = UNNotificationAction(identifier: Action.acceptDrop, title: "Accept", options: [])
        let decline = UNNotificationAction(identifier: Action.declineDrop, title: "Decline", options: [.destructive])
        let cancelDrop = UNNotificationAction(identifier: Action.cancelDrop, title: "Cancel", options: [.destructive])
        let got = UNNotificationCategory(identifier: Category.shareGot, actions: [show], intentIdentifiers: [], options: [])
        let ask = UNNotificationCategory(identifier: Category.shareAsk, actions: [accept, decline], intentIdentifiers: [], options: [])
        let wait = UNNotificationCategory(identifier: Category.shareWait, actions: [cancelDrop], intentIdentifiers: [], options: [])
        center.setNotificationCategories([available, ready, grace, pressure, pair, got, ask, wait])
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

    /// `categoryId` (one of `Category`) attaches the update action buttons.
    func remove(id: String) {
        guard Self.supported else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    func send(title: String, body: String, id: String, categoryId: String? = nil, quiet: Bool = false) {
        guard Self.supported else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = quiet ? nil : .default
        if quiet { content.interruptionLevel = .passive }
        if let categoryId { content.categoryIdentifier = categoryId }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.notice(.app, "couldn't post notification \"\(id)\"", error: error) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Without this, the system suppresses banners while Vitals is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// A banner-body tap does the category's primary action; "Later" just dismisses.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        let resolved: UpdateAction?
        switch action {
        case Action.download:
            resolved = .download
        case Action.install:
            resolved = .install
        case UNNotificationDefaultActionIdentifier:
            // Only update categories map to an action. Tapping an alert
            // notification must never start an update.
            switch category {
            case Category.updateReady:     resolved = .install
            case Category.updateAvailable: resolved = .download
            default:                       resolved = nil
            }
        default:
            resolved = nil  // "Later", dismiss, or an unrelated category
        }
        let identifier = response.notification.request.identifier
        let remote = Self.remoteAction(action, identifier: identifier)
        let share = Self.shareAction(action, identifier: identifier)
        await MainActor.run {
            if let resolved { self.onUpdateAction?(resolved) }
            if let remote { self.onRemoteAction?(remote) }
            if let share { self.onShareAction?(share) }
        }
    }

    /// Maps a tapped action on a remote notification back to what the remote model should do.
    nonisolated static func remoteAction(_ action: String, identifier: String) -> RemoteAction? {
        switch action {
        case Action.cancelCommand: return .cancelCommand(identifier)
        case Action.calmDown: return .calmDown
        case Action.allowPair, Action.denyPair:
            let prefix = pairNotificationId("")
            guard identifier.hasPrefix(prefix) else { return nil }
            return .resolvePair(id: String(identifier.dropFirst(prefix.count)), allow: action == Action.allowPair)
        default: return nil
        }
    }

    nonisolated static func shareAction(_ action: String, identifier: String) -> ShareAction? {
        func dropId(_ category: String) -> String? {
            let prefix = shareNotificationId(category, "")
            return identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : nil
        }
        switch action {
        case Action.showDrop: return dropId(Category.shareGot).map(ShareAction.show)
        case UNNotificationDefaultActionIdentifier: return dropId(Category.shareGot).map(ShareAction.show)
        case Action.acceptDrop: return dropId(Category.shareAsk).map { .decide($0, accept: true) }
        case Action.declineDrop: return dropId(Category.shareAsk).map { .decide($0, accept: false) }
        case Action.cancelDrop: return dropId(Category.shareWait).map(ShareAction.cancel)
        default: return nil
        }
    }
}
