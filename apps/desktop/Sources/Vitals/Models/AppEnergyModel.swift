import SwiftUI
import Darwin

/// State for the Battery hub's per-app energy list: the live, app-grouped energy
/// usage plus who's holding a sleep assertion. Samples on a timer only while the
/// hub is visible (started/stopped by the view), mirroring `ProcessesModel`.
@MainActor
final class AppEnergyModel: ObservableObject {
    /// Apps by energy use, highest first (real watts when available, else the
    /// Energy-Impact index).
    @Published private(set) var apps: [AppEnergyUsage] = []
    @Published private(set) var hasLoaded = false
    /// Set when the process list can't be read at all (restricted environment).
    @Published private(set) var loadFailed = false
    /// True when the OS reported real per-process energy for at least one app —
    /// so the UI knows whether it's showing watts or the relative impact index.
    @Published private(set) var usesRealWatts = false

    private let inventory = ProcessInventory()
    private var timer: Timer?
    private var isScrolling = false
    private static let ownBundlePath = Bundle.main.bundleURL.standardizedFileURL.path

    /// Apps keeping the Mac (or its display) awake right now.
    var sleepBlockers: [AppEnergyUsage] { apps.filter(\.preventsSleep) }

    /// Total measured app power in watts, or nil when no app reported real energy
    /// (so the UI shows the honest "—" rather than a fabricated sum).
    var totalWatts: Double? {
        let measured = apps.compactMap(\.avgWatts)
        return measured.isEmpty ? nil : measured.reduce(0, +)
    }

    // MARK: Sampling lifecycle

    func start() {
        refresh()
        guard timer == nil else { return }
        // 2.5s — energy deltas want a slightly longer window than the process
        // list's 2s to read cleanly, and this list changes slowly.
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Pause refreshes while the user scrolls the list (republishing mid-scroll
    /// rebuilds the rows and stutters), taking one immediately when it stops.
    func setScrolling(_ scrolling: Bool) {
        guard scrolling != isScrolling else { return }
        isScrolling = scrolling
        if !scrolling { refresh() }
    }

    func refresh() {
        guard !isScrolling else { return }
        Task {
            let sampled = await inventory.sample(includeSystem: false)
            guard !self.isScrolling else { return }
            guard let processes = sampled else {
                self.loadFailed = true
                self.hasLoaded = true
                return
            }
            let usage = AppEnergy.usage(from: processes,
                                        assertions: PowerAssertions.current(),
                                        ownBundlePath: Self.ownBundlePath)
            self.loadFailed = false
            self.apps = usage
            self.usesRealWatts = usage.contains { $0.avgWatts != nil }
            self.hasLoaded = true
        }
    }
}
