import Foundation

struct PressureGuard {
    enum Rule: String, CaseIterable, Sendable {
        case memoryPressure, swapGrowth, cpuSaturated, agentOverload, emulatorStack, thermal
    }

    struct Inputs: Sendable {
        let now: Date
        let pressureLevel: Int
        let swapUsed: UInt64
        let cpuPercent: Double?
        let thermalLevel: Int
        let memoryTotal: UInt64
        let classified: ProcessGroups.Classified
        let table: [ProcessSampler.Row]
    }

    enum Change: Equatable, Sendable {
        case raised(WireAlert)
        case cleared(WireAlert)
    }

    static let clearAfter: TimeInterval = 60
    static let swapWindow: TimeInterval = 60

    static let defaultSettings = GuardSettings(
        enabled: true,
        cooldownSeconds: 600,
        rules: [
            GuardRule(kind: Rule.memoryPressure.rawValue, enabled: true, threshold: 2, holdSeconds: 10),
            GuardRule(kind: Rule.swapGrowth.rawValue, enabled: true, threshold: 4, holdSeconds: 0),
            GuardRule(kind: Rule.cpuSaturated.rawValue, enabled: true, threshold: 90, holdSeconds: 60),
            GuardRule(kind: Rule.agentOverload.rawValue, enabled: true, threshold: 6, holdSeconds: 20),
            GuardRule(kind: Rule.emulatorStack.rawValue, enabled: true, threshold: 2, holdSeconds: 10),
            GuardRule(kind: Rule.thermal.rawValue, enabled: true, threshold: 2, holdSeconds: 0)
        ]
    )

    private struct RuleState {
        var since: Date?
        var falseSince: Date?
        var active: WireAlert?
        var lastRaised: Date = .distantPast
    }

    var settings: GuardSettings
    private var states: [Rule: RuleState] = [:]
    private var swapSamples: [(Date, UInt64)] = []

    init(settings: GuardSettings) { self.settings = settings }

    var active: [WireAlert] { Rule.allCases.compactMap { states[$0]?.active } }

    mutating func evaluate(_ inputs: Inputs) -> [Change] {
        swapSamples.append((inputs.now, inputs.swapUsed))
        swapSamples.removeAll { inputs.now.timeIntervalSince($0.0) > Self.swapWindow }
        guard settings.enabled else {
            let cleared = active.map { Change.cleared(clear($0, at: inputs.now)) }
            states.removeAll()
            return cleared
        }
        var changes: [Change] = []
        for rule in Rule.allCases {
            guard let config = settings.rules.first(where: { $0.kind == rule.rawValue }), config.enabled else {
                if let alert = states[rule]?.active { changes.append(.cleared(clear(alert, at: inputs.now))) }
                states[rule] = nil
                continue
            }
            var state = states[rule] ?? RuleState()
            let firing = condition(rule, threshold: config.threshold, inputs: inputs)
            if firing {
                state.falseSince = nil
                if state.since == nil { state.since = inputs.now }
                let held = inputs.now.timeIntervalSince(state.since ?? inputs.now) >= Double(config.holdSeconds)
                let cooled = inputs.now.timeIntervalSince(state.lastRaised) >= Double(settings.cooldownSeconds)
                if state.active == nil, held, cooled {
                    let alert = makeAlert(rule, inputs: inputs)
                    state.active = alert
                    state.lastRaised = inputs.now
                    changes.append(.raised(alert))
                }
            } else {
                state.since = nil
                if let alert = state.active {
                    if state.falseSince == nil { state.falseSince = inputs.now }
                    if inputs.now.timeIntervalSince(state.falseSince ?? inputs.now) >= Self.clearAfter {
                        changes.append(.cleared(clear(alert, at: inputs.now)))
                        state.active = nil
                        state.falseSince = nil
                    }
                }
            }
            states[rule] = state
        }
        return changes
    }

    private func clear(_ alert: WireAlert, at date: Date) -> WireAlert {
        WireAlert(
            id: alert.id, rule: alert.rule, severity: alert.severity, summary: alert.summary,
            raisedAt: alert.raisedAt, clearedAt: Int64(date.timeIntervalSince1970 * 1000),
            groups: alert.groups, plan: alert.plan
        )
    }

    private func condition(_ rule: Rule, threshold: Double, inputs: Inputs) -> Bool {
        switch rule {
        case .memoryPressure:
            return Double(inputs.pressureLevel) >= threshold
        case .swapGrowth:
            guard let oldest = swapSamples.first else { return false }
            let growth = Double(inputs.swapUsed) - Double(oldest.1)
            return Double(inputs.swapUsed) > threshold * 1_073_741_824 && growth >= 512 * 1_048_576
        case .cpuSaturated:
            return (inputs.cpuPercent ?? 0) >= threshold
        case .agentOverload:
            let agents = inputs.classified.totals(for: .agents)
            return Double(agents.count) >= threshold || Double(agents.memory) > Double(inputs.memoryTotal) * 0.4
        case .emulatorStack:
            return Double(inputs.classified.totals(for: .emulators).count) >= threshold && inputs.pressureLevel >= 1
        case .thermal:
            return Double(inputs.thermalLevel) >= threshold
        }
    }

    private func severity(_ rule: Rule, inputs: Inputs) -> String {
        switch rule {
        case .memoryPressure: return inputs.pressureLevel >= 2 ? "critical" : "warning"
        case .emulatorStack: return "critical"
        case .thermal: return inputs.thermalLevel >= 3 ? "critical" : "warning"
        default: return "warning"
        }
    }

    private func makeAlert(_ rule: Rule, inputs: Inputs) -> WireAlert {
        let agents = inputs.classified.totals(for: .agents)
        let emulators = inputs.classified.totals(for: .emulators)
        let summary: String
        switch rule {
        case .memoryPressure: summary = "Memory pressure is high: \(agents.count) agent processes, \(emulators.count) emulator processes"
        case .swapGrowth: summary = "Swap is growing fast (\(Self.gigabytes(inputs.swapUsed)) GB used)"
        case .cpuSaturated: summary = "CPU has been saturated for a minute"
        case .agentOverload: summary = "\(agents.count) agent processes are using \(Self.gigabytes(agents.memory)) GB"
        case .emulatorStack: summary = "\(emulators.count) emulator processes running under memory pressure"
        case .thermal: summary = "Thermal pressure is up; macOS is throttling"
        }
        return WireAlert(
            id: UUID().uuidString.lowercased(),
            rule: rule.rawValue,
            severity: severity(rule, inputs: inputs),
            summary: summary,
            raisedAt: Int64(inputs.now.timeIntervalSince1970 * 1000),
            clearedAt: nil,
            groups: Self.wireTotals(inputs.classified),
            plan: Self.calmPlan(inputs.table, classified: inputs.classified)
        )
    }

    static func calmPlan(_ table: [ProcessSampler.Row], classified: ProcessGroups.Classified) -> WireCalmPlan {
        var actions: [ProcessAction] = []
        var paused = 0
        var throttled = 0
        for row in table {
            let ref = ProcessRef(pid: row.pid, startTimeMs: row.startTimeMs)
            switch classified.group(of: row.pid) {
            case .emulators where row.cpuPercent < 5 && (row.name.hasPrefix("qemu-system") || row.name == "emulator"):
                actions.append(ProcessAction(target: ref, action: .pause))
                paused += 1
            case .agents:
                actions.append(ProcessAction(target: ref, action: .throttle))
                throttled += 1
            default:
                break
            }
        }
        var parts: [String] = []
        if paused > 0 { parts.append("pause \(paused) idle emulator\(paused == 1 ? "" : "s")") }
        if throttled > 0 { parts.append("lower priority of \(throttled) agent process\(throttled == 1 ? "" : "es")") }
        let summary = parts.isEmpty ? "Nothing to calm right now" : parts.joined(separator: ", ").capitalizedFirst
        return WireCalmPlan(actions: Array(actions.prefix(64)), summary: summary)
    }

    static func wireTotals(_ classified: ProcessGroups.Classified) -> [WireGroupTotals] {
        classified.totals.map {
            WireGroupTotals(group: $0.group.rawValue, count: $0.count, cpuPercent: $0.cpuPercent, memoryBytes: Double($0.memory))
        }
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
