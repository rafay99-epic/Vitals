import Foundation
import os
import Sentry

enum ErrorReporting {
    static let enabledKey = "errorReportsEnabled"

    private static var dsn: String {
        Channel.current == .stable
            ? "https://8366e6b56aff057459b81f26180108ac@o4512219615920128.ingest.us.sentry.io/4512333592526848"
            : "https://ad2098bcc6654fb435e6681fa29adc55@o4512219615920128.ingest.us.sentry.io/4512333983252480"
    }

    private static let running = OSAllocatedUnfairLock(initialState: false)
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    private static let toggles = DispatchQueue(label: "com.syntaxlab.vitals.error-reporting", qos: .utility)

    private static let privateCategories: Set<LogCategory> = [.uninstall, .cleanup]

    static var isRunning: Bool { running.withLock { $0 } }

    static func startIfEnabled(_ defaults: UserDefaults = .standard) {
        if defaults.object(forKey: enabledKey) as? Bool ?? true { start() }
    }

    static func setEnabled(_ on: Bool) {
        toggles.async {
            if on {
                start()
            } else if running.withLock({ was in defer { was = false }; return was }) {
                SentrySDK.close()
            }
        }
    }

    private static func start() {
        guard running.withLock({ was in defer { was = true }; return !was }) else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = Channel.current.rawValue
            options.releaseName = "vitals-macos@\(Updater.currentVersion)"
            if let build = Bundle.main.object(forInfoDictionaryKey: "VitalsBuildNumber") as? String { options.dist = build }
            options.sendDefaultPii = false
            options.enableAppHangTracking = true
            options.enableMetricKit = true
            options.enableLogs = true
            options.beforeSend = { event in scrubbed(event) }
            options.beforeBreadcrumb = { crumb in
                crumb.message = crumb.message.map { Scrub.text($0) }
                crumb.data = crumb.data.map(scrubbed)
                return crumb
            }
            options.beforeSendLog = { log in
                log.body = Scrub.text(log.body)
                return log
            }
        }
    }

    static func record(_ level: LogLevel, _ category: LogCategory, _ message: String, source: Log.Source, error: Log.ErrorInfo?) {
        guard isRunning else { return }
        let hidden = privateCategories.contains(category)
        if hidden && level < .error { return }
        let body = hidden ? "\(category.title) failed" : Scrub.text(message)
        var attributes: [String: Any] = ["category": category.rawValue, "source": "\(source.file):\(source.line)"]
        if let error {
            attributes["error.type"] = error.type
            attributes["error.domain"] = error.domain
            attributes["error.code"] = error.code
            if !hidden { attributes["error.description"] = Scrub.text(error.description) }
        }
        switch level {
        case .fault: SentrySDK.logger.fatal(body, attributes: attributes)
        case .error: SentrySDK.logger.error(body, attributes: attributes)
        default: SentrySDK.logger.info(body, attributes: attributes)
        }
        guard level >= .error else { return }
        let key = "\(source.file):\(source.line)"
        guard reported.withLock({ $0.insert(key).inserted }) else { return }
        let event = Event(level: level == .fault ? .fatal : .error)
        event.message = SentryMessage(formatted: body)
        event.tags = ["category": category.rawValue, "source": key]
        event.extra = attributes
        event.fingerprint = [category.rawValue, source.file, String(source.line)]
        SentrySDK.capture(event: event)
    }

    private static func scrubbed(_ event: Event) -> Event {
        event.serverName = nil
        if let formatted = event.message?.formatted { event.message = SentryMessage(formatted: Scrub.text(formatted)) }
        event.exceptions?.forEach { exception in exception.value = exception.value.map { Scrub.text($0) } }
        event.breadcrumbs?.forEach { crumb in crumb.message = crumb.message.map { Scrub.text($0) } }
        event.debugMeta?.forEach { image in image.codeFile = image.codeFile.map { Scrub.home($0) } }
        let stacks = (event.exceptions ?? []).compactMap(\.stacktrace) + (event.threads ?? []).compactMap(\.stacktrace)
        for frame in stacks.flatMap(\.frames) {
            frame.package = frame.package.map { Scrub.home($0) }
            frame.fileName = frame.fileName.map { Scrub.home($0) }
        }
        if var context = event.context, var device = context["device"] {
            device.removeValue(forKey: "name")
            context["device"] = device
            event.context = context
        }
        return event
    }

    private static func scrubbed(_ data: [String: Any]) -> [String: Any] {
        data.mapValues { ($0 as? String).map { Scrub.text($0) } ?? $0 }
    }
}
