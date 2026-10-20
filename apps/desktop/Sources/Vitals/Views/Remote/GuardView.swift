import SwiftUI

struct GuardView: View {
    @Environment(RemoteModel.self) private var remote
    @Environment(AppSettings.self) private var settings

    var body: some View {
        MetricScroll {
            SectionCard(title: "Right now", symbol: "gauge.with.dots.needle.67percent") {
                if settings.guardSettings.enabled, let state = remote.guardState {
                    HStack(spacing: 24) {
                        stat("Memory pressure", state.pressure.capitalized)
                        stat("Thermal", state.thermal.capitalized)
                        stat("Swap", memoryText(state.swapUsedBytes))
                        Spacer()
                    }
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        ForEach(state.groups.filter { $0.count > 0 && $0.group != "protected" }, id: \.group) { group in
                            GridRow {
                                Text(group.group.prefix(1).uppercased() + group.group.dropFirst())
                                Text("\(group.count)").monospacedDigit()
                                Text(String(format: "%.0f%% CPU", group.cpuPercent)).monospacedDigit().foregroundStyle(.secondary)
                                Text(memoryText(group.memoryBytes))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.callout)
                    HStack {
                        Button("Calm down now") { remote.calmDown() }
                        Button("Undo") { remote.undoCalm() }.disabled(!state.calmApplied)
                    }
                } else {
                    Text(settings.guardSettings.enabled ? "Waiting for the first process sweep." : "Pressure Guard is off.")
                        .foregroundStyle(.secondary)
                }
            }
            if settings.guardSettings.enabled, let active = remote.guardState?.active, !active.isEmpty {
                SectionCard(title: "Active alerts", symbol: "exclamationmark.triangle") {
                    ForEach(active) { alert in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.summary).foregroundStyle(alert.severity == "critical" ? .red : .orange)
                            Text(alert.plan.summary).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            SectionCard(title: "Rules", symbol: "slider.horizontal.3") {
                Toggle("Pressure Guard", isOn: Binding(
                    get: { settings.guardSettings.enabled },
                    set: { update(enabled: $0) }
                ))
                ForEach(settings.guardSettings.rules, id: \.kind) { rule in
                    Toggle(title(rule.kind), isOn: Binding(
                        get: { rule.enabled },
                        set: { update(rule: rule.kind, ruleEnabled: $0) }
                    ))
                    .disabled(!settings.guardSettings.enabled)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
    }

    private func title(_ kind: String) -> String {
        switch kind {
        case "memoryPressure": return "Memory pressure critical for 10 s"
        case "swapGrowth": return "Swap above 4 GB and growing"
        case "cpuSaturated": return "CPU above 90% for a minute"
        case "agentOverload": return "Six or more agent processes, or agents above 40% of RAM"
        case "emulatorStack": return "Two or more emulators under memory pressure"
        case "thermal": return "Thermal pressure serious or worse"
        default: return kind
        }
    }

    private func update(enabled: Bool? = nil, rule: String? = nil, ruleEnabled: Bool? = nil) {
        let current = settings.guardSettings
        let rules = current.rules.map {
            $0.kind == rule
                ? GuardRule(kind: $0.kind, enabled: ruleEnabled ?? $0.enabled, threshold: $0.threshold, holdSeconds: $0.holdSeconds)
                : $0
        }
        remote.applyGuardSettings(GuardSettings(enabled: enabled ?? current.enabled, cooldownSeconds: current.cooldownSeconds, rules: rules))
    }
}

@MainActor private let memoryFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    return formatter
}()

@MainActor private func memoryText(_ bytes: Double) -> String {
    memoryFormatter.string(fromByteCount: Int64(max(0, bytes)))
}
