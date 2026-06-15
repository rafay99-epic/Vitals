import Testing
import Foundation
@testable import Vitals

/// Locks the launch-item safety boundary: only the user's own non-Apple agents
/// may be toggled (root-free, reversible) — Apple's items and anything
/// system-domain are read-only. Also locks the friendly-name extraction.
struct LaunchItemTests {
    private func item(label: String, program: String?, kind: LaunchItem.Kind) -> LaunchItem {
        LaunchItem(label: label, program: program, plistPath: URL(fileURLWithPath: "/tmp/x.plist"),
                   kind: kind, runAtLoad: true, disabled: false)
    }

    @Test func appleItemsAreNeverActionable() {
        #expect(item(label: "com.apple.something", program: nil, kind: .userAgent).isActionable == false)
        #expect(item(label: "com.apple.daemon", program: nil, kind: .systemDaemon).isActionable == false)
        #expect(item(label: "com.thirdparty.agent", program: nil, kind: .userAgent).isActionable)
    }

    @Test func escalationMatchesDomain() {
        // Disable: agents use the no-password gui override; only daemons need admin.
        #expect(item(label: "x", program: nil, kind: .userAgent).disableNeedsAdmin == false)
        #expect(item(label: "x", program: nil, kind: .systemAgent).disableNeedsAdmin == false)
        #expect(item(label: "x", program: nil, kind: .systemDaemon).disableNeedsAdmin)
        // Remove: your own agent trashes its plist; anything in /Library needs admin.
        #expect(item(label: "x", program: nil, kind: .userAgent).removeNeedsAdmin == false)
        #expect(item(label: "x", program: nil, kind: .systemAgent).removeNeedsAdmin)
        #expect(item(label: "x", program: nil, kind: .systemDaemon).removeNeedsAdmin)
    }

    @Test func displayNamePrefersAppName() {
        let app = item(label: "com.foo.helper", program: "/Applications/Foo Bar.app/Contents/MacOS/helper", kind: .userAgent)
        #expect(app.displayName == "Foo Bar")
    }

    @Test func displayNameFallsBackToLabel() {
        #expect(item(label: "com.foo.agent", program: "/usr/local/bin/foo", kind: .userAgent).displayName == "com.foo.agent")
        #expect(item(label: "com.foo.agent", program: nil, kind: .userAgent).displayName == "com.foo.agent")
    }

    @Test func parsesLaunchctlOverrideStates() {
        let text = """
        \tdisabled services = {
        \t\t"com.disabled.one" => disabled
        \t\t"com.enabled.two" => enabled
        \t}
        """
        let map = LaunchItemScanner.parseOverrides(text)
        #expect(map["com.disabled.one"] == true)
        #expect(map["com.enabled.two"] == false)
        #expect(map["com.absent.three"] == nil)   // no override → fall back to plist key
    }
}
