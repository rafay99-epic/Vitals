import Testing
import Foundation
@testable import Vitals

/// The launch-argument deep links must only ever act on an exact, valid
/// `--flag value` pair — anything absent, trailing, or unknown falls through
/// to the normal defaults rather than guessing.
struct LaunchOverridesTests {
    @Test func readsTheTokenAfterTheFlag() {
        #expect(LaunchOverrides.value(for: "--section", in: ["app", "--section", "history"]) == "history")
    }

    @Test func absentFlagIsNil() {
        #expect(LaunchOverrides.value(for: "--section", in: ["app"]) == nil)
    }

    @Test func trailingFlagWithoutValueIsNil() {
        #expect(LaunchOverrides.value(for: "--section", in: ["app", "--section"]) == nil)
    }

    @Test func sectionAndMetricIdsMatchTheEnums() {
        // The ids scripts pass are the enums' raw values — lock a couple so a
        // rawValue rename can't silently break the deep link.
        #expect(NavSection(rawValue: "history") == .history)
        #expect(NavSection(rawValue: "network") == .network)
        #expect(HistoryView.Metric(rawValue: "network") == .network)
        #expect(NavSection(rawValue: "bogus") == nil)
    }
}
