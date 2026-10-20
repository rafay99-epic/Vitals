import Foundation
import AppKit

@MainActor
enum RunningApps {
    static func list() -> [WireRunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier > 0 && $0.processIdentifier != getpid() }
            .map {
                WireRunningApp(
                    pid: $0.processIdentifier,
                    bundleId: $0.bundleIdentifier,
                    name: $0.localizedName ?? $0.bundleIdentifier ?? "App",
                    active: $0.isActive,
                    hidden: $0.isHidden
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func quit(_ app: AppRef) -> String? { act(app) { $0.terminate() } }
    static func hide(_ app: AppRef) -> String? { act(app) { $0.hide() } }
    static func forceQuit(_ app: AppRef) -> String? { act(app) { $0.forceTerminate() } }

    static func launch(bundleId: String) async -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return "App not installed" }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func act(_ ref: AppRef, _ body: (NSRunningApplication) -> Bool) -> String? {
        guard let app = NSRunningApplication(processIdentifier: ref.pid),
              ref.bundleId == nil || app.bundleIdentifier == ref.bundleId,
              app.processIdentifier != getpid()
        else { return "App is no longer running" }
        return body(app) ? nil : "The app declined"
    }
}
