import Foundation
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
        case AssertType.idleDisplay:
            kind = .display
        default:
            return nil   // not a sleep assertion — ignore
        }
        return PowerAssertion(kind: kind, type: type, name: entry[Key.name] as? String)
    }
}
