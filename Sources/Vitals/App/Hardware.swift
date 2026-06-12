import Foundation
import AppKit

enum Hardware {
    /// True only on Apple Silicon hardware. Queries the machine, so it is
    /// correct even when this process runs as the x86_64 slice under Rosetta.
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    /// Shows an apology and exits. Reached only on Intel Macs (the universal
    /// binary's x86_64 slice runs just far enough to display this).
    @MainActor
    static func showUnsupportedAndQuit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Vitals requires an Apple Silicon Mac"
        alert.informativeText = """
        We're sorry — Vitals isn't supported on Intel-based Macs.

        It reads temperatures and controls fans through Apple Silicon (M-series) \
        hardware that Intel Macs don't have. Please run Vitals on an Apple Silicon Mac.
        """
        alert.addButton(withTitle: "Quit")

        app.activate(ignoringOtherApps: true)
        alert.runModal()
        exit(0)
    }
}
