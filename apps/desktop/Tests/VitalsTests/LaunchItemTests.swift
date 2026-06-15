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

    @Test func onlyUserNonAppleItemsAreToggleable() {
        #expect(item(label: "com.thirdparty.agent", program: nil, kind: .userAgent).canToggle)
        #expect(!item(label: "com.apple.something", program: nil, kind: .userAgent).canToggle)   // Apple, never
        #expect(!item(label: "com.thirdparty.agent", program: nil, kind: .systemAgent).canToggle) // system
        #expect(!item(label: "com.thirdparty.daemon", program: nil, kind: .systemDaemon).canToggle)
    }

    @Test func displayNamePrefersAppName() {
        let app = item(label: "com.foo.helper", program: "/Applications/Foo Bar.app/Contents/MacOS/helper", kind: .userAgent)
        #expect(app.displayName == "Foo Bar")
    }

    @Test func displayNameFallsBackToLabel() {
        #expect(item(label: "com.foo.agent", program: "/usr/local/bin/foo", kind: .userAgent).displayName == "com.foo.agent")
        #expect(item(label: "com.foo.agent", program: nil, kind: .userAgent).displayName == "com.foo.agent")
    }
}
