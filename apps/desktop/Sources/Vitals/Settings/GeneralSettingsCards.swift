import SwiftUI
import UserNotifications

// MARK: - General cards

struct ReadingsCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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
    }
}

struct PowerSettingsCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsCard(title: "Power", symbol: "bolt.fill", tint: .green) {
            settingsRow("Power source") {
                HStack(spacing: 5) {
                    Image(systemName: settings.isOnBattery ? "battery" : "powercord")
                        .symbolRenderingMode(.hierarchical)
                    Text(settings.isOnBattery ? "Battery" : "AC")
                        .monospacedDigit()
                }
                .font(.system(size: 12.5))
                .foregroundStyle(settings.isOnBattery ? .green : .secondary)
            }
            SwitchRow(
                label: "Reduce sampling on battery",
                caption: "Doubles the sampling interval (capped at 5 s) while on battery. Low Power Mode slows sampling to 10 s regardless.",
                isOn: $settings.reduceOnBattery
            )
            settingsRow("Sampling rate") {
                Text("Every \(settings.effectiveRefreshInterval, format: .number) s")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if settings.isLowPowerMode {
                Label("Low Power Mode is on, so Vitals samples every 10 s to match macOS.", systemImage: "leaf.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct AppearanceCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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
        }
    }
}

struct ApplicationCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsCard(title: "Applications", symbol: "macwindow", tint: .teal) {
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

// MARK: - Menu bar

struct MenuBarCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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
            }
            .disabled(!settings.showMenuBar)
            .opacity(settings.showMenuBar ? 1 : 0.5)
        }
    }
}

// MARK: - Cleanup

struct CleanupCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsCard(title: "Cleanup", symbol: "sparkles", tint: .orange) {
            SwitchRow(
                label: "Scan automatically on open",
                caption: "Off by default — Cleanup waits for you to press Scan. Cleaning always needs selection and confirmation.",
                isOn: $settings.autoScanCleanup
            )
        }
    }
}

// MARK: - Alerts cards

struct OverheatingCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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
    }
}

struct NotificationsCard: View {
    @Environment(AppSettings.self) private var settings
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var settings = settings
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
        .task { await refreshNotificationStatus() }
    }

    private var hasAnyAlert: Bool {
        settings.notifyOverheat || settings.notifyThermal
    }

    private func refreshNotificationStatus() async {
        guard NotificationManager.supported else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
    }
}
