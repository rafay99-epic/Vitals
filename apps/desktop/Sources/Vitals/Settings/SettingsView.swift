import SwiftUI
import AppKit
import UserNotifications
import UniformTypeIdentifiers

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
                    label: "Liquid Glass",
                    caption: "Translucent window with glass cards. Requires macOS 26.",
                    isOn: $settings.liquidGlass
                )
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
                .disabled(!settings.liquidGlass)
                .opacity(settings.liquidGlass ? 1 : 0.5)
            }

            SettingsCard(title: "Menu bar", symbol: "menubar.rectangle", tint: .blue) {
                SwitchRow(label: "Show in menu bar", isOn: $settings.showMenuBar)
                settingsRow("Display") {
                    Picker("", selection: $settings.menuBarMode) {
                        ForEach(MenuBarMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.showMenuBar)
                }
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
                if notificationsDenied && (settings.notifyOverheat || settings.notifyThermal) {
                    Label(
                        "Notifications are turned off for Vitals. Enable them in System Settings → Notifications → Vitals.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .task { await refreshNotificationStatus() }
    }

    private func refreshNotificationStatus() async {
        guard NotificationManager.supported else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
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
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([HistoryLogger.fileURL])
                        }
                    }
                    .controlSize(.small)
                    .disabled(!logFileExists)
                }
                Text("One line every 10 seconds while Vitals runs (\(logSizeText)). Open the CSV in Numbers or Excel to study long-term trends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logFileExists: Bool {
        FileManager.default.fileExists(atPath: HistoryLogger.fileURL.path)
    }

    private var logSizeText: String {
        guard let size = try? FileManager.default.attributesOfItem(atPath: HistoryLogger.fileURL.path)[.size] as? UInt64 else {
            return "no file yet"
        }
        return "currently " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "vitals-history.csv"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: HistoryLogger.fileURL, to: destination)
        }
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
                    Text(Updater.currentVersion)
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
                            Button("Install Vitals \(release.version)") {
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

    private var updateStatusLine: String {
        switch updater.status {
        case .idle:
            return "Updates install from this project's GitHub releases."
        case .checking:
            return "Checking for updates…"
        case .upToDate:
            let when = updater.lastChecked.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "You're up to date. Last checked \(when)."
        case .available(let release):
            return "Vitals \(release.version) is ready to install."
        case .downloading:
            return "Downloading update…"
        case .installing:
            return "Installing — Vitals will relaunch in a moment."
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
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? Updater.currentVersion
        if build == Updater.currentVersion {
            return "Version \(Updater.currentVersion)"
        }
        return "Version \(Updater.currentVersion) (build \(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Vitals")
                    .font(.system(size: 18, weight: .semibold))
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
