import Foundation
import AppKit
import IOKit.pwr_mgt

/// A single power-management assertion held by a process — the mechanism apps use
/// to keep the Mac (or just its display) awake. Reading them needs no privileges.
struct PowerAssertion: Equatable {
    enum Kind: Equatable {
        /// Prevents idle/system sleep — keeps the whole Mac awake and draining.
        case system
        /// Prevents display sleep — keeps the screen on (e.g. video playback).
        case display
    }
    let kind: Kind
    /// Raw assertion type, e.g. "PreventUserIdleSystemSleep".
    let type: String
    /// Caller-supplied description of the activity, e.g. "Playing a movie".
    let name: String?

    var preventsSystemSleep: Bool { kind == .system }
}

/// Reads which processes are currently holding power assertions — the honest
/// answer to "what's keeping my Mac awake?". A thin wrapper over
/// `IOPMCopyAssertionsByProcess`; the parsing is split out so it's testable
/// without the live power-management state.
enum PowerAssertions {
    // The IOKit key/type names are `CFSTR(...)` macros, which don't import into
    // Swift, so we use their literal string values (constant names in comments).
    private enum Key {
        static let type = "AssertType"   // kIOPMAssertionTypeKey
        static let name = "AssertName"   // kIOPMAssertionNameKey
    }
    private enum AssertType {
        static let idleSystem  = "PreventUserIdleSystemSleep"   // kIOPMAssertPreventUserIdleSystemSleep
        static let system      = "PreventSystemSleep"           // kIOPMAssertionTypePreventSystemSleep
        static let noIdle      = "NoIdleSleepAssertion"         // kIOPMAssertionTypeNoIdleSleep
        static let idleDisplay = "PreventUserIdleDisplaySleep"  // kIOPMAssertPreventUserIdleDisplaySleep
        static let noDisplay   = "NoDisplaySleepAssertion"      // kIOPMAssertionTypeNoDisplaySleep (legacy)
    }

    /// Assertions currently held, keyed by owning pid. Empty when nothing is
    /// keeping the Mac awake.
    static func current() -> [pid_t: [PowerAssertion]] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let raw = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [:] }
        return parse(raw)
    }

    /// Pure mapping from `IOPMCopyAssertionsByProcess`'s shape (pid → array of
    /// assertion dictionaries) to typed, sleep-relevant assertions. Assertion
    /// types unrelated to sleep, and malformed entries, are dropped.
    static func parse(_ raw: [NSNumber: [[String: Any]]]) -> [pid_t: [PowerAssertion]] {
        var result: [pid_t: [PowerAssertion]] = [:]
        for (pidNumber, entries) in raw {
            let pid = pid_t(truncating: pidNumber)
            guard pid > 0 else { continue }
            let assertions = entries.compactMap(assertion(from:))
            if !assertions.isEmpty { result[pid] = assertions }
        }
        return result
    }

    private static func assertion(from entry: [String: Any]) -> PowerAssertion? {
        guard let type = entry[Key.type] as? String else { return nil }
        let kind: PowerAssertion.Kind
        switch type {
        case AssertType.idleSystem, AssertType.system, AssertType.noIdle:
            kind = .system
        case AssertType.idleDisplay, AssertType.noDisplay:
            kind = .display
        default:
            return nil   // not a sleep assertion — ignore
        }
        return PowerAssertion(kind: kind, type: type, name: entry[Key.name] as? String)
    }
}

/// A user app keeping the Mac (or its display) awake.
struct SleepBlocker: Identifiable {
    let id: pid_t
    let name: String
    let bundleURL: URL?
    let reason: String?
    let preventsSystemSleep: Bool
}

extension PowerAssertions {
    /// Current assertions held by the user's own processes, each attributed to
    /// its app (a helper climbs to the app that launched it). System daemons
    /// are left out, so an empty list means "no *apps* are keeping it awake".
    static func blockers() -> [SleepBlocker] {
        let me = getuid()
        var byApp: [pid_t: SleepBlocker] = [:]
        for (pid, assertions) in current() {
            guard let info = bsdInfo(pid), info.pbi_uid == me, pid != getpid() else { continue }
            let owner = owningApp(of: pid, parent: pid_t(info.pbi_ppid))
            let system = assertions.contains(where: \.preventsSystemSleep)
            let reason = assertions.lazy.compactMap(\.name).first
            let existing = byApp[owner.pid]
            byApp[owner.pid] = SleepBlocker(
                id: owner.pid,
                name: owner.app?.localizedName ?? processName(pid),
                bundleURL: owner.app?.bundleURL,
                reason: existing?.reason ?? reason,
                preventsSystemSleep: (existing?.preventsSystemSleep ?? false) || system
            )
        }
        return byApp.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func owningApp(of pid: pid_t, parent: pid_t) -> (pid: pid_t, app: NSRunningApplication?) {
        var current = pid
        var next = parent
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy != .prohibited {
                return (current, app)
            }
            guard next > 1, let info = bsdInfo(next) else { break }
            current = next
            next = pid_t(info.pbi_ppid)
        }
        return (pid, nil)
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        let name = String(cString: buffer)
        return name.isEmpty ? "pid \(pid)" : name
    }
}
