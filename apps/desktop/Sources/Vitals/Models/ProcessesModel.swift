import SwiftUI
import AppKit
import Darwin

/// State for the Processes tab: the live, app-grouped process list and the
/// quit / force-quit actions. Sampling runs on a timer only while the tab is
/// visible (started/stopped by the view).
@MainActor
final class ProcessesModel: ObservableObject {
    /// One row: a single process, or an app with all its helper processes
    /// folded together (so "Brave" is one line, not 18).
    struct Group: Identifiable {
        let id: String
        let name: String
        let bundleURL: URL?         // non-nil → a real .app, shown with its icon
        let pids: [pid_t]
        let memoryBytes: UInt64
        let cpuPercent: Double
        let killable: Bool          // every process is the current user's
        var isApp: Bool { bundleURL != nil }
        var processCount: Int { pids.count }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case memory, cpu, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .memory: return "Memory"
            case .cpu: return "CPU"
            case .name: return "Name"
            }
        }
    }

    /// A quit awaiting confirmation (force quit always confirms; a normal quit
    /// only when the user opted into confirmation).
    struct PendingQuit: Identifiable {
        enum Kind { case quit, force }
        let id = UUID()
        let kind: Kind
        let group: Group
    }

    @Published private(set) var groups: [Group] = []
    @Published private(set) var hasLoaded = false
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .memory
    @Published var pendingQuit: PendingQuit?

    /// Set by the view from settings before sampling.
    var includeSystem = false
    var groupHelpers = true

    private let inventory = ProcessInventory()
    private var timer: Timer?

    var filteredGroups: [Group] {
        var result = groups
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOrder {
        case .memory: result.sort { $0.memoryBytes > $1.memoryBytes }
        case .cpu:    result.sort { $0.cpuPercent > $1.cpuPercent }
        case .name:   result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return result
    }

    var totalMemoryBytes: UInt64 { groups.reduce(0) { $0 + $1.memoryBytes } }
    var appCount: Int { groups.filter(\.isApp).count }

    // MARK: Sampling lifecycle

    /// Begin sampling (every 2s) and take a first reading immediately.
    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
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

    func refresh() {
        let includeSystem = includeSystem
        let groupHelpers = groupHelpers
        Task {
            let processes = await inventory.sample(includeSystem: includeSystem)
            self.groups = Self.grouped(processes, groupHelpers: groupHelpers)
            self.hasLoaded = true
        }
    }

    private static func grouped(_ processes: [RunningProcess], groupHelpers: Bool) -> [Group] {
        var buckets: [String: [RunningProcess]] = [:]
        var order: [String] = []
        for process in processes {
            let key = (groupHelpers ? process.bundleURL?.path : nil) ?? "pid:\(process.id)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(process)
        }
        return order.map { key in
            let items = buckets[key]!
            let lead = items[0]
            return Group(
                id: key,
                name: lead.name,
                bundleURL: lead.bundleURL,
                pids: items.map(\.id),
                memoryBytes: items.reduce(0) { $0 + $1.memoryBytes },
                cpuPercent: items.reduce(0) { $0 + $1.cpuPercent },
                killable: items.allSatisfy(\.ownedByCurrentUser)
            )
        }
    }

    // MARK: Quitting

    /// Quit gracefully. Confirms first only if the user enabled confirmation —
    /// a normal quit lets the app save (it isn't destructive), so one click is
    /// the default.
    func requestQuit(_ group: Group, confirm: Bool) {
        if confirm {
            pendingQuit = PendingQuit(kind: .quit, group: group)
        } else {
            perform(.quit, group)
        }
    }

    /// Force quit always confirms — it kills the process outright and can lose
    /// unsaved work.
    func requestForceQuit(_ group: Group) {
        pendingQuit = PendingQuit(kind: .force, group: group)
    }

    func confirmPending() {
        guard let pending = pendingQuit else { return }
        perform(pending.kind, pending.group)
        pendingQuit = nil
    }

    private func perform(_ kind: PendingQuit.Kind, _ group: Group) {
        guard group.killable else { return }
        let force = kind == .force
        // Apps quit through NSRunningApplication so they can run their normal
        // (save-aware) termination; bare processes get a signal.
        if let url = group.bundleURL {
            let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL == url }
            if !running.isEmpty {
                running.forEach { _ = force ? $0.forceTerminate() : $0.terminate() }
                scheduleQuickRefresh()
                return
            }
        }
        let signal = force ? SIGKILL : SIGTERM
        for pid in group.pids { _ = kill(pid, signal) }
        scheduleQuickRefresh()
    }

    /// Re-read shortly after a quit so the row disappears without waiting for
    /// the next tick.
    private func scheduleQuickRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }
}
