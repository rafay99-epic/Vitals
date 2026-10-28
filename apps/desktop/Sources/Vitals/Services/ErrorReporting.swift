import Foundation
import os
import Sentry

/// Sends crashes, hangs, uncaught exceptions and logged errors to Sentry (org
/// `syntax-lab-tecnology`, project `vitals-macos`), scrubbed by `Scrub` first. On unless the owner
/// turns it off in Settings → Developer → Crash reports.
///
/// Sits beside `CrashReporter`, which keeps writing the same crashes into `vitals.log` for Report a
/// Problem. Started only from the GUI process, never the `--fan-daemon` path or tests.
enum ErrorReporting {
    /// UserDefaults key, read here before `AppSettings` exists so a crash during launch is caught.
    static let enabledKey = "errorReportsEnabled"

    /// Public by design: a DSN only lets an app send events to this project.
    private static let dsn = "https://8366e6b56aff057459b81f26180108ac@o4512219615920128.ingest.us.sentry.io/4512333592526848"

    private static let running = OSAllocatedUnfairLock(initialState: false)
    /// Source lines already reported this launch, so a failure in a loop is one event, not thousands.
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Turning reports on or off at runtime: `close()` flushes for up to two seconds, so off the main thread.
    private static let toggles = DispatchQueue(label: "com.syntaxlab.vitals.error-reporting", qos: .utility)

    /// Their lines name the owner's apps and files, so only where they failed is sent, never the text.
    private static let privateCategories: Set<LogCategory> = [.uninstall, .cleanup]

    static var isRunning: Bool { running.withLock { $0 } }

    /// Call once at launch, after `CrashReporter.install()`, so Sentry's handlers chain to it.
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
            // Not `enableUncaughtNSExceptionReporting`: it makes AppKit crash on exceptions it would
            // survive, so the app would behave differently with reports on. Uncaught ones still land.
            options.enableAppHangTracking = true
            // macOS's own diagnostics: hangs, CPU spikes and runaway disk writes it caught.
            options.enableMetricKit = true
            // Sentry Logs: `record` sends every `Log` line at notice or above as a searchable log.
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

    /// Called by `Log` for every line at notice or above while reports are on. Each becomes a
    /// Sentry log line; errors and faults also become events, once per source line per launch.
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
        // Group by where it was logged, not by the message, which often carries a changing value.
        event.fingerprint = [category.rawValue, source.file, String(source.line)]
        SentrySDK.capture(event: event)
    }

    /// Nothing that names the Mac or its owner: no server name, no device name, messages scrubbed,
    /// and the home folder out of image and frame paths (an app run from ~/Downloads, a Dev build).
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
