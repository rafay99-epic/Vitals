import Foundation

/// Evaluates the user's custom alert rules each tick. Holds per-rule timing
/// state — when the condition first became true (for the "sustained for N
/// minutes" gate) and when it last fired (a cooldown so one ongoing problem
/// notifies once, not every tick). It decides *whether* to fire and returns the
/// triggered rules; the caller formats and sends the notification (so unit
/// preferences stay with the model). The core decision is a pure function, so
/// the sustain/cooldown behaviour is unit-tested without a clock.
@MainActor
final class AlertEngine {
    struct RuleState: Equatable {
        var trueSince: Date? = nil
        var lastFired: Date = .distantPast
    }

    /// One ongoing problem re-notifies at most this often.
    static let cooldown: TimeInterval = 600

    private var states: [UUID: RuleState] = [:]

    /// Advances every enabled rule and returns those that should fire now, with
    /// the value that triggered them.
    func evaluate(rules: [AlertRule], readings: AlertReadings, now: Date) -> [(rule: AlertRule, value: Double)] {
        // Forget state for rules that were deleted.
        let active = Set(rules.map(\.id))
        states = states.filter { active.contains($0.key) }

        var fired: [(AlertRule, Double)] = []
        for rule in rules where rule.enabled {
            let value = readings.value(for: rule.metric)
            let prior = states[rule.id] ?? RuleState()
            let (next, shouldFire) = Self.step(rule: rule, value: value, state: prior, now: now, cooldown: Self.cooldown)
            states[rule.id] = next
            if shouldFire, let value { fired.append((rule, value)) }
        }
        return fired
    }

    /// Pure state transition for one rule. Returns the new state and whether to
    /// fire. Firing needs the condition satisfied continuously for the rule's
    /// duration *and* the cooldown to have elapsed since the last fire.
    static func step(rule: AlertRule, value: Double?, state: RuleState,
                     now: Date, cooldown: TimeInterval) -> (RuleState, fire: Bool) {
        var state = state
        guard let value, rule.isSatisfied(by: value) else {
            state.trueSince = nil   // condition broke — reset the sustain clock
            return (state, false)
        }
        if state.trueSince == nil { state.trueSince = now }
        let heldFor = now.timeIntervalSince(state.trueSince ?? now)
        guard heldFor >= rule.sustainedMinutes * 60,
              now.timeIntervalSince(state.lastFired) >= cooldown
        else { return (state, false) }
        state.lastFired = now
        return (state, true)
    }
}
