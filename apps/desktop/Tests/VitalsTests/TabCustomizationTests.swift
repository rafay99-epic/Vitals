import Testing
import Foundation
@testable import Vitals

/// Locks the navigation customization rules: defaults show every tab in order,
/// hiding keeps a tab in the order but off the bar, the Dashboard can never be
/// hidden, and a saved order from an older version never drops or duplicates a
/// tab (new ones are appended).
@MainActor
struct TabCustomizationTests {
    // A unique suite per test (keyed to the calling test's name) so parallel
    // tests never share a UserDefaults store and wipe each other — the cause of
    // a CI-only flake. `#function` resolves at the call site to the test method.
    private func freshSettings(_ id: String = #function,
                               configure: (UserDefaults) -> Void = { _ in }) -> AppSettings {
        let name = "vitals.test.tabs.\(id)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        configure(suite)
        return AppSettings(defaults: suite, configURL: nil)
    }

    @Test func defaultsToSmallMonitoringFirstNav() {
        let settings = freshSettings()
        // The full order contains every tab (so nothing is unreachable)…
        #expect(settings.tabOrder == AppTab.defaultOrder)
        #expect(Set(settings.tabOrder) == Set(AppTab.allCases))
        // …but only the small monitoring-first set is shown by default.
        #expect(settings.visibleTabs == AppTab.defaultVisible)
        #expect(settings.hiddenTabs == Set(AppTab.defaultHidden))
        // The deep-dive / management tabs start hidden, the Dashboard never does.
        #expect(settings.hiddenTabs.contains(.cleanup))
        #expect(!settings.hiddenTabs.contains(.dashboard))
    }

    @Test func hidingRemovesFromBarButKeepsOrder() {
        let settings = freshSettings()
        settings.hiddenTabs.insert(.storage)
        #expect(!settings.visibleTabs.contains(.storage))
        #expect(settings.tabOrder.contains(.storage))
    }

    @Test func dashboardCannotBeHidden() {
        let settings = freshSettings()
        settings.hiddenTabs.insert(.dashboard)  // forced — the UI disables this
        #expect(settings.visibleTabs.contains(.dashboard))
    }

    @Test func storedOrderGetsMissingTabsAppended() {
        // A saved order from a version that predated most tabs.
        let settings = freshSettings { $0.set("storage,gpu", forKey: "tabOrder") }
        #expect(Array(settings.tabOrder.prefix(2)) == [.storage, .gpu])
        #expect(Set(settings.tabOrder) == Set(AppTab.allCases))  // nothing dropped
        #expect(settings.tabOrder.count == AppTab.allCases.count)  // nothing duplicated
    }

    @Test func newDeepDiveTabStaysHiddenForUpgradingUser() {
        // An upgrading user whose saved layout predates a deep-dive tab: both
        // their stored order and stored hidden set omit it. The new tab must be
        // appended to the order AND default to hidden (it ships hidden) — never
        // barge into their nav bar. Simulate with a layout missing `.cpu`.
        let order = AppTab.allCases.filter { $0 != .cpu }.map(\.rawValue).joined(separator: ",")
        let hidden = AppTab.defaultHidden.filter { $0 != .cpu }.map(\.rawValue).joined(separator: ",")
        let settings = freshSettings {
            $0.set(order, forKey: "tabOrder")
            $0.set(hidden, forKey: "hiddenTabs")
        }
        #expect(settings.tabOrder.contains(.cpu))          // appended, reachable
        #expect(settings.hiddenTabs.contains(.cpu))         // but hidden by default
        #expect(!settings.visibleTabs.contains(.cpu))       // so it's off the bar
        // A tab the user had already chosen to show stays shown (not re-hidden).
        #expect(settings.visibleTabs.contains(.dashboard))
    }

    @Test func reorderingFollowsThroughToVisibleTabs() {
        let settings = freshSettings()
        // Swapping the first two (both visible by default) puts the second first.
        settings.tabOrder.swapAt(0, 1)
        #expect(settings.visibleTabs.first == AppTab.defaultOrder[1])
    }
}
