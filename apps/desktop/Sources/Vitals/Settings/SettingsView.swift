import SwiftUI
import AppKit
import UserNotifications

/// Settings in the same design language as the main window: capsule tabs,
/// card sections with tinted icon tiles, switch toggles.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general, alerts, data, updates, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .alerts: return "Alerts"
            case .data: return "Data"
            case .updates: return "Updates"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .alerts: return "bell.badge"
            case .data: return "doc.text"
            case .updates: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }
    }

    @State private var tab: Tab = .general
    @Namespace private var tabIndicator

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.vertical, 10)
            Divider()
                .opacity(0.5)
            ScrollView {
                Group {
                    switch tab {
                    case .general: GeneralPane()
                    case .alerts: AlertsPane()
                    case .data: DataPane()
                    case .updates: UpdatesPane()
                    case .about: AboutPane()
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 600)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { item in
                tabButton(item)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    private func tabButton(_ item: Tab) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                tab = item
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tab == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if tab == item {
                Capsule()
                    .fill(.quaternary)
                    .matchedGeometryEffect(id: "settings-tab", in: tabIndicator)
            }
        }
    }
}

// MARK: - Card building blocks

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct SwitchRow: View {
    let label: String
    var caption: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5))
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// One selectable menu-bar reading: a tinted icon tile, its label, and a switch
/// that adds/removes it from the shown set.
private struct MenuBarMetricToggle: View {
    let metric: MenuBarMetric
    @Binding var selection: Set<MenuBarMetric>

    var body: some View {
        Toggle(isOn: Binding(
            get: { selection.contains(metric) },
            set: { on in
                if on { selection.insert(metric) } else { selection.remove(metric) }
            }
        )) {
            HStack(spacing: 8) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.blue.opacity(0.14))
                    )
                Text(metric.label)
                    .font(.system(size: 12.5))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

// MARK: - Tabs customization

/// Navigation-bar customization: label display mode, size, and a show / reorder
/// list. Reordering uses arrows rather than drag — predictable, keyboard- and
/// VoiceOver-friendly, and a clean fit for the card design.
private struct TabsCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsCard(title: "Tabs", symbol: "menubar.rectangle", tint: .indigo) {
            settingsRow("Labels") {
                Picker("", selection: $settings.tabDisplayMode) {
                    ForEach(TabDisplayMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            settingsRow("Size") {
                Picker("", selection: $settings.tabSize) {
                    ForEach(TabSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                Text("Show & reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(settings.tabOrder.enumerated()), id: \.element) { index, tab in
                    TabReorderRow(tab: tab, index: index)
                }
                Text("Reorder with the arrows and switch off tabs you don't need. The Dashboard always stays, and ⌘1–9 follow this order.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct TabReorderRow: View {
    @EnvironmentObject private var settings: AppSettings
    let tab: AppTab
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                moveButton(systemName: "chevron.up", delta: -1, disabled: index == 0)
                moveButton(systemName: "chevron.down", delta: 1, disabled: index == settings.tabOrder.count - 1)
            }
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.indigo)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.indigo.opacity(0.14)))
            Text(tab.title)
                .font(.system(size: 12.5))
            Spacer()
            Toggle("", isOn: visibility)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!tab.canHide)
                .help(tab.canHide ? "Show \(tab.title) in the navigation bar" : "The Dashboard is always shown")
        }
    }

    private func moveButton(systemName: String, delta: Int, disabled: Bool) -> some View {
        Button {
            let target = index + delta
            guard settings.tabOrder.indices.contains(index),
                  settings.tabOrder.indices.contains(target) else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                settings.tabOrder.swapAt(index, target)
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
        .disabled(disabled)
    }

    private var visibility: Binding<Bool> {
        Binding(
            get: { !settings.hiddenTabs.contains(tab) },
            set: { visible in
                if visible {
                    settings.hiddenTabs.remove(tab)
                } else if tab.canHide {
                    settings.hiddenTabs.insert(tab)
                }
            }
        )
    }
}

private func settingsRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
    HStack {
        Text(label)
            .font(.system(size: 12.5))
        Spacer()
        control()
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var widgets: WidgetManager

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Readings", symbol: "thermometer.medium", tint: .orange) {
                settingsRow("Temperature unit") {
                    Picker("", selection: $settings.unit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                settingsRow("Refresh every") {
                    Picker("", selection: $settings.refreshInterval) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                settingsRow("Chart history") {
                    Picker("", selection: $settings.historyMinutes) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("30 minutes").tag(30)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(title: "Appearance", symbol: "paintbrush", tint: .purple) {
                settingsRow("Theme") {
                    Picker("", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SwitchRow(
                    label: "GPU acceleration",
                    caption: "Use the GPU for Liquid Glass and animations. Turn off for opaque, motionless cards that stay light on the GPU — handy while gaming, compiling, or on battery.",
                    isOn: $settings.gpuAcceleration
                )
                SwitchRow(
                    label: "Liquid Glass",
                    caption: "Translucent window with glass cards. Needs GPU acceleration and macOS 26.",
                    isOn: $settings.liquidGlass
                )
                .disabled(!Hardware.supportsLiquidGlass || !settings.gpuAcceleration)
                .opacity(Hardware.supportsLiquidGlass && settings.gpuAcceleration ? 1 : 0.5)
                if !Hardware.supportsLiquidGlass {
                    Label(
                        "Turned off automatically — this Mac has no hardware GPU (it's a virtual machine), so translucency would be software-rendered and use far too much memory.",
                        systemImage: "cube.transparent"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    settingsRow("Frosting") {
                        Slider(value: $settings.glassIntensity, in: 0...1)
                            .frame(width: 170)
                    }
                    HStack {
                        Spacer()
                        HStack {
                            Text("Clear")
                            Spacer()
                            Text("Frosted")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 170)
                    }
                }
                .disabled(!settings.glassEnabled)
                .opacity(settings.glassEnabled ? 1 : 0.5)
            }

            TabsCard()

            SettingsCard(title: "Menu bar", symbol: "menubar.rectangle", tint: .blue) {
                SwitchRow(label: "Show in menu bar", isOn: $settings.showMenuBar)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Readings to show")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(MenuBarMetric.allCases) { metric in
                            MenuBarMetricToggle(metric: metric, selection: $settings.menuBarMetrics)
                        }
                        Text("Turn all off to show just the icon.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    settingsRow("Style") {
                        Picker("", selection: $settings.menuBarUseIcons) {
                            Text("Icons").tag(true)
                            Text("Text").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    SwitchRow(
                        label: "Animate icons",
                        caption: "Gently spins the fan and breathes the rest. Needs GPU acceleration.",
                        isOn: $settings.menuBarAnimated
                    )
                    .disabled(!settings.menuBarUseIcons || !settings.gpuAcceleration)
                    .opacity(settings.menuBarUseIcons && settings.gpuAcceleration ? 1 : 0.5)
                }
                .disabled(!settings.showMenuBar)
                .opacity(settings.showMenuBar ? 1 : 0.5)
            }

            SettingsCard(title: "Processes", symbol: "list.bullet", tint: .green) {
                SwitchRow(
                    label: "Group app helpers",
                    caption: "Fold an app's helper processes into one row (e.g. Brave's many helpers → a single “Brave”).",
                    isOn: $settings.groupHelperProcesses
                )
                SwitchRow(
                    label: "Show system processes",
                    caption: "Also list root and background processes. They can't be quit without admin rights, so they're hidden by default.",
                    isOn: $settings.showSystemProcesses
                )
                SwitchRow(
                    label: "Confirm before quitting",
                    caption: "Ask before a normal Quit. Force Quit always asks regardless.",
                    isOn: $settings.confirmBeforeQuittingProcess
                )
            }

            SettingsCard(title: "Storage", symbol: "internaldrive", tint: .blue) {
                SwitchRow(
                    label: "Analyze automatically on open",
                    caption: "Off by default — analysis walks your disk, so the Storage tab waits for you to press Analyze.",
                    isOn: $settings.autoAnalyzeStorage
                )
                SwitchRow(
                    label: "Include hidden files",
                    caption: "Count dotfiles and hidden folders (caches, the Trash). Applies on the next analyze.",
                    isOn: $settings.analyzerIncludesHidden
                )
                SwitchRow(
                    label: "Allow scanning the whole disk",
                    caption: "Adds a Scan whole disk action that walks every folder from the top of your drive, including system areas. It can take a while and use the disk heavily — Vitals confirms before each run.",
                    isOn: $settings.allowWholeDiskScan
                )
            }

            SettingsCard(title: "Cleanup", symbol: "sparkles", tint: .orange) {
                SwitchRow(
                    label: "Scan automatically on open",
                    caption: "Off by default — Cleanup waits for you to press Scan. Cleaning always needs selection and confirmation.",
                    isOn: $settings.autoScanCleanup
                )
            }

            SettingsCard(title: "Desktop Widgets", symbol: "square.grid.2x2", tint: .pink) {
                Text("Live panels on your desktop, from the same readings as the app. They sit behind your windows; drag to place, close from the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(WidgetKind.allCases) { kind in
                    SwitchRow(
                        label: kind.title,
                        isOn: Binding(
                            get: { widgets.isVisible(kind) },
                            set: { _ in widgets.toggle(kind) }
                        )
                    )
                }
                Divider().opacity(0.5)
                SwitchRow(
                    label: "Float on top of windows",
                    caption: "Off: widgets stay on the desktop, behind your windows (default). On: they float above everything.",
                    isOn: Binding(get: { widgets.onTop }, set: { widgets.onTop = $0 })
                )
                SwitchRow(
                    label: "Animate widgets",
                    caption: "Widgets react to their readings: a rim glow that breathes with severity and a fan that spins faster as RPM climbs. Off: perfectly still panels.",
                    isOn: $settings.animateWidgets
                )
            }

            SettingsCard(title: "Application", symbol: "macwindow", tint: .teal) {
                SwitchRow(label: "Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                SwitchRow(
                    label: "Hide Dock icon",
                    caption: "Runs Vitals as a menu-bar-only app while the menu bar item is shown.",
                    isOn: $settings.hideDockIcon
                )
                .disabled(!settings.showMenuBar)
            }
        }
    }
}

// MARK: - Alerts

private struct AlertsPane: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var notificationsDenied = false
    @State private var expandedRule: UUID?

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Overheating", symbol: "flame", tint: .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hot threshold")
                            .font(.system(size: 12.5))
                        Spacer()
                        Text(settings.formatWithUnit(settings.warnThreshold, decimals: 0))
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                    Slider(value: $settings.warnThreshold, in: 60...100, step: 1)
                    Text("Above this average CPU temperature, the menu bar icon becomes a flame and the overheat alert can fire.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Notifications", symbol: "bell.badge", tint: .red) {
                SwitchRow(label: "Notify when the CPU stays hot", isOn: $settings.notifyOverheat)
                SwitchRow(label: "Notify on high thermal pressure", isOn: $settings.notifyThermal)
                if notificationsDenied && hasAnyAlert {
                    Label(
                        "Notifications are turned off for Vitals. Enable them in System Settings → Notifications → Vitals.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            SettingsCard(title: "Custom alerts", symbol: "bell.badge.waveform", tint: .blue) {
                if settings.alertRules.isEmpty {
                    Text("Build your own alerts — get notified when a temperature, fan, disk, battery, or process crosses a line you set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($settings.alertRules) { $rule in
                        AlertRuleRow(
                            rule: $rule,
                            isExpanded: Binding(
                                get: { expandedRule == rule.id },
                                set: { expandedRule = $0 ? rule.id : nil }
                            ),
                            onDelete: { settings.alertRules.removeAll { $0.id == rule.id } }
                        )
                        if rule.id != settings.alertRules.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
                Button {
                    let rule = AlertRule(metric: .cpuTemp)
                    settings.alertRules.append(rule)
                    expandedRule = rule.id
                } label: {
                    Label("Add alert", systemImage: "plus.circle")
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .task { await refreshNotificationStatus() }
    }

    private var hasAnyAlert: Bool {
        settings.notifyOverheat || settings.notifyThermal || settings.alertRules.contains(where: \.enabled)
    }

    private func refreshNotificationStatus() async {
        guard NotificationManager.supported else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
    }
}

/// One custom-alert row: a plain-language sentence with an enable switch, that
/// expands into an editor (metric, condition, threshold, sustain). The threshold
/// is stored canonically (°C) but shown/edited in the user's temperature unit.
private struct AlertRuleRow: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var rule: AlertRule
    @Binding var isExpanded: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Toggle("", isOn: $rule.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                Image(systemName: rule.metric.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.blue.opacity(0.14)))
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Text(sentence)
                            .font(.system(size: 12.5))
                            .foregroundStyle(rule.enabled ? .primary : .secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if isExpanded { editor }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsRow("Metric") {
                Picker("", selection: metricBinding) {
                    ForEach(AlertMetric.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            settingsRow("Condition") {
                Picker("", selection: $rule.comparison) {
                    ForEach(AlertComparison.allCases) { Text($0.label.capitalized).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Threshold").font(.system(size: 12.5))
                    Spacer()
                    Text(displayThreshold)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
                Slider(value: thresholdBinding, in: thresholdRange, step: sliderStep)
            }
            settingsRow("Sustained for") {
                Stepper(value: $rule.sustainedMinutes, in: 0...30, step: 1) {
                    Text(rule.sustainedMinutes == 0 ? "Immediately" : "\(Int(rule.sustainedMinutes)) min")
                        .font(.system(size: 12.5)).monospacedDigit()
                }
                .fixedSize()
            }
            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(.leading, 30)
        .padding(.top, 2)
    }

    /// Switching the metric resets the condition + threshold to that metric's
    /// sensible defaults, so a 90% threshold never carries over to "free disk".
    private var metricBinding: Binding<AlertMetric> {
        Binding(
            get: { rule.metric },
            set: { metric in
                rule.metric = metric
                rule.comparison = metric.defaultComparison
                rule.threshold = metric.defaultThreshold
            }
        )
    }

    private var thresholdRange: ClosedRange<Double> {
        let range = rule.metric.range
        guard rule.metric.isTemperature else { return range }
        return settings.display(range.lowerBound)...settings.display(range.upperBound)
    }

    private var sliderStep: Double { rule.metric.isTemperature ? 1 : rule.metric.step }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { rule.metric.isTemperature ? settings.display(rule.threshold) : rule.threshold },
            set: { shown in
                if rule.metric.isTemperature {
                    rule.threshold = settings.unit == .fahrenheit ? (shown - 32) * 5 / 9 : shown
                } else {
                    rule.threshold = shown
                }
            }
        )
    }

    private var displayThreshold: String {
        if rule.metric.isTemperature {
            return "\(Int(settings.display(rule.threshold).rounded()))\(settings.unit.symbol)"
        }
        switch rule.metric {
        case .fanRPM:   return "\(Int(rule.threshold)) rpm"
        case .diskFree: return "\(Int(rule.threshold)) GB"
        default:        return "\(Int(rule.threshold))%"
        }
    }

    private var sentence: String {
        var line = "\(rule.metric.label) \(rule.comparison.label) \(displayThreshold)"
        if rule.sustainedMinutes > 0 { line += " for \(Int(rule.sustainedMinutes)) min" }
        return line
    }
}

// MARK: - Data

private struct DataPane: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Logging", symbol: "doc.text", tint: .indigo) {
                SwitchRow(label: "Log readings to disk", isOn: $settings.loggingEnabled)
                settingsRow("History file") {
                    HStack(spacing: 8) {
                        Button("Export…") { exportCSV() }
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([HistoryLogger.fileURL])
                        }
                    }
                    .controlSize(.small)
                    .disabled(!logFileExists)
                }
                Text("One line every 10 seconds while Vitals runs (\(logSizeText)). Stored in \(folderDisplayPath); Export saves a timestamped copy to \(folderDisplayPath)/exports. Open the CSV in Numbers or Excel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logFileExists: Bool {
        FileManager.default.fileExists(atPath: HistoryLogger.fileURL.path)
    }

    private var folderDisplayPath: String {
        (DataHome.directory.path as NSString).abbreviatingWithTildeInPath
    }

    private static let exportStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private var logSizeText: String {
        guard let size = try? FileManager.default.attributesOfItem(atPath: HistoryLogger.fileURL.path)[.size] as? UInt64 else {
            return "no file yet"
        }
        return "currently " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Writes a timestamped copy of the log into the data home's `exports/`
    /// folder and reveals it — the fixed, predictable location, rather than a
    /// save panel.
    private func exportCSV() {
        let exports = DataHome.exportsDirectory
        try? FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let destination = exports.appendingPathComponent(
            "vitals-history-\(Self.exportStampFormatter.string(from: Date())).csv")
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.copyItem(at: HistoryLogger.fileURL, to: destination)) != nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
}

// MARK: - Updates

private struct UpdatesPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "Software updates", symbol: "arrow.down.circle", tint: .green) {
                settingsRow("Installed version") {
                    Text(installedVersion)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                SwitchRow(label: "Check for updates automatically", isOn: $settings.autoUpdateCheck)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Check for Updates") {
                            Task { await updater.check(userInitiated: true) }
                        }
                        .disabled(updater.isBusy)
                        if case .available(let release) = updater.status {
                            Button("Install \(Channel.current.displayName) \(release.displayVersion)") {
                                Task { await updater.downloadAndInstall() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .controlSize(.small)
                    Text(updateStatusLine)
                        .font(.caption)
                        .foregroundStyle(updateStatusIsError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
        }
    }

    private var installedVersion: String {
        let build = Updater.currentBuildNumber
        return build > 0 ? "\(Updater.currentVersion) (build \(build))" : Updater.currentVersion
    }

    private var updateStatusLine: String {
        switch updater.status {
        case .idle:
            return Channel.current.isDev
                ? "Dev tracks the newest pre-release build on GitHub."
                : "Updates install from this project's GitHub releases."
        case .checking:
            return "Checking for updates…"
        case .upToDate:
            let when = updater.lastChecked.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "You're up to date. Last checked \(when)."
        case .available(let release):
            return "\(Channel.current.displayName) \(release.displayVersion) is ready to install."
        case .downloading:
            return "Downloading update…"
        case .installing:
            return "Installing — \(Channel.current.displayName) will relaunch in a moment."
        case .failed(let message):
            return message
        }
    }

    private var updateStatusIsError: Bool {
        if case .failed = updater.status { return true }
        return false
    }
}

// MARK: - About

private struct AboutPane: View {
    private static let company = "Syntax Lab Technology"
    private static let developer = "Abdul Rafay"
    private static let developerURL = URL(string: "https://rafay99.com")!
    private static let repoURL = URL(string: "https://github.com/\(Updater.repository)")!
    private static let licenseURL = URL(string: "https://github.com/\(Updater.repository)/blob/main/LICENSE")!
    private static let moleURL = URL(string: "https://github.com/tw93/mole")!

    private var versionLine: String {
        var line: String
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? Updater.currentVersion
        if build == Updater.currentVersion {
            line = "Version \(Updater.currentVersion)"
        } else {
            line = "Version \(Updater.currentVersion) (build \(build))"
        }
        // Dev builds stamp the exact branch@sha so you know what's running.
        if let info = Channel.buildInfo { line += " · \(info)" }
        return line
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                HStack(spacing: 7) {
                    Text(Channel.current.displayName)
                        .font(.system(size: 18, weight: .semibold))
                    if let badge = Channel.current.badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange))
                            .foregroundStyle(.white)
                    }
                }
                Text(versionLine)
                    .font(.system(.callout, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Take care of your Mac.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            SettingsCard(title: "Company", symbol: "building.2", tint: .blue) {
                settingsRow("Made by") {
                    Text(Self.company)
                        .font(.system(size: 12.5, weight: .medium))
                }
                settingsRow("Developer") {
                    Link("\(Self.developer) — rafay99.com", destination: Self.developerURL)
                        .font(.system(size: 12.5))
                }
                settingsRow("Source code") {
                    Link("github.com/\(Updater.repository)", destination: Self.repoURL)
                        .font(.system(size: 12.5))
                }
            }

            SettingsCard(title: "License", symbol: "checkmark.seal", tint: .green) {
                settingsRow("License") {
                    Link("GNU GPL v3.0", destination: Self.licenseURL)
                        .font(.system(size: 12.5))
                }
                Text("Vitals is free software: you may use, study, modify, and redistribute it under the same terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Acknowledgements", symbol: "heart", tint: .pink) {
                settingsRow("Mole") {
                    Link("github.com/tw93/mole", destination: Self.moleURL)
                        .font(.system(size: 12.5))
                }
                Text("The Applications & Cleanup feature is informed by Mole (GPL-3.0) — its catalog of app-leftover locations and safety-first uninstall design shaped Vitals' implementation. Full credit and thanks to its authors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
