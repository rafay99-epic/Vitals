import SwiftUI
import AppKit
import UserNotifications
import UniformTypeIdentifiers

/// Settings, organized into tabs now that one long form outgrew itself:
/// General · Alerts · Data · Updates · About.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AlertsSettingsTab()
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
            DataSettingsTab()
                .tabItem { Label("Data", systemImage: "doc.text") }
            UpdatesSettingsTab()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 560)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Readings") {
                Picker("Temperature unit", selection: $settings.unit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Refresh every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }

                Picker("Chart history", selection: $settings.historyMinutes) {
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("30 minutes").tag(30)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Liquid Glass", isOn: $settings.liquidGlass)
                    Text("Translucent window with glass cards. Requires macOS 26.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Menu bar") {
                Toggle("Show in menu bar", isOn: $settings.showMenuBar)

                Picker("Display", selection: $settings.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .disabled(!settings.showMenuBar)
            }

            Section("Application") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hide Dock icon", isOn: $settings.hideDockIcon)
                        .disabled(!settings.showMenuBar)
                    Text("Runs Vitals as a menu-bar-only app. Available while the menu bar item is shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Alerts

private struct AlertsSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section("Overheating") {
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $settings.warnThreshold, in: 60...100, step: 1) {
                        Text("Hot threshold")
                    }
                    Text("Above \(settings.format(settings.warnThreshold, decimals: 0)) average CPU, the menu bar icon becomes a flame and the overheat alert can fire.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                Toggle("Notify when the CPU stays hot", isOn: $settings.notifyOverheat)
                Toggle("Notify on high thermal pressure", isOn: $settings.notifyThermal)

                if notificationsDenied && (settings.notifyOverheat || settings.notifyThermal) {
                    Text("Notifications are turned off for Vitals. Enable them in System Settings → Notifications → Vitals.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refreshNotificationStatus() }
    }

    private func refreshNotificationStatus() async {
        guard NotificationManager.supported else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
    }
}

// MARK: - Data

private struct DataSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Logging") {
                Toggle("Log readings to disk", isOn: $settings.loggingEnabled)

                LabeledContent("History file") {
                    HStack {
                        Button("Export…") { exportCSV() }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([HistoryLogger.fileURL])
                        }
                    }
                    .disabled(!logFileExists)
                }

                Text("One line every 10 seconds while Vitals runs (\(logSizeText)). Open the CSV in Numbers or Excel to study long-term trends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

private struct UpdatesSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Form {
            Section("Software updates") {
                LabeledContent("Installed version", value: Updater.currentVersion)
                Toggle("Check for updates automatically", isOn: $settings.autoUpdateCheck)

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
                    Text(updateStatusLine)
                        .font(.caption)
                        .foregroundStyle(updateStatusIsError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
        }
        .formStyle(.grouped)
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

private struct AboutSettingsTab: View {
    private static let repoURL = "https://github.com/\(Updater.repository)"
    private static let licenseURL = "\(repoURL)/blob/main/LICENSE"
    private static let moleURL = "https://github.com/tw93/mole"
    private static let developerURL = "https://rafay99.com"

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vitals")
                            .font(.title3.weight(.semibold))
                        Text("Version \(Updater.currentVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Take care of your Mac.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Company") {
                LabeledContent("Made by", value: "Syntax Lab Technology")
                LabeledContent("Developer") {
                    Link("Abdul Rafay — rafay99.com", destination: URL(string: Self.developerURL)!)
                }
                LabeledContent("Source code") {
                    Link("github.com/\(Updater.repository)", destination: URL(string: Self.repoURL)!)
                }
            }

            Section("License") {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("License") {
                        Link("GNU GPL v3.0", destination: URL(string: Self.licenseURL)!)
                    }
                    Text("Vitals is free software: you may use, study, modify, and redistribute it under the same terms.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Acknowledgements") {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Mole") {
                        Link("github.com/tw93/mole", destination: URL(string: Self.moleURL)!)
                    }
                    Text("The Applications & Cleanup feature is informed by Mole (GPL-3.0) — its catalog of app-leftover locations and safety-first uninstall design shaped Vitals' implementation. Full credit and thanks to its authors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
