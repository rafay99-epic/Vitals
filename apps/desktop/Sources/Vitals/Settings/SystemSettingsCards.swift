import SwiftUI
import AppKit

// MARK: - Updates card

struct SoftwareUpdatesCard: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var settings = settings
        SettingsCard(title: "Software updates", symbol: "arrow.down.circle", tint: .green) {
            settingsRow("Installed version") {
                Text(installedVersion)
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if Channel.current.updatesEnabled {
                SwitchRow(label: "Check for updates automatically", isOn: $settings.autoUpdateCheck)
                SwitchRow(
                    label: "Download updates automatically",
                    caption: "Pre-download in the background so installing is instant. You still confirm before it installs.",
                    isOn: $settings.autoDownloadUpdates
                )
                .disabled(!settings.autoUpdateCheck)
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
                        } else if case .readyToInstall(let release) = updater.status {
                            Button("Install & Relaunch \(release.displayVersion)") {
                                Task { await updater.installPending() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .controlSize(.small)
                    Text(updateStatusLine)
                        .font(.caption)
                        .foregroundStyle(updateStatusIsError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            } else {
                Text("Dev builds don't auto-update — rebuild with ./dev.sh to change versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            return Channel.current.isPrerelease
                ? "Nightly tracks the newest pre-release build on GitHub."
                : "Updates install from this project's GitHub releases."
        case .checking:
            return "Checking for updates…"
        case .upToDate:
            let when = updater.lastChecked.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "You're up to date. Last checked \(when)."
        case .available(let release):
            return "\(Channel.current.displayName) \(release.displayVersion) is ready to install."
        case .readyToInstall(let release):
            return "\(Channel.current.displayName) \(release.displayVersion) downloaded — ready to install."
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

// MARK: - Data cards

struct LoggingCard: View {
    @Environment(AppSettings.self) private var settings
    @State private var refresh = 0
    @State private var exportStatus: String?

    var body: some View {
        @Bindable var settings = settings
        let _ = refresh
        SettingsCard(title: "Logging", symbol: "doc.text", tint: .indigo) {
            SwitchRow(label: "Log readings to disk", isOn: $settings.loggingEnabled)
            settingsRow("History database") {
                HStack(spacing: 8) {
                    Button("Export CSV…") { exportCSV() }
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([DataHome.historyDatabaseFile])
                    }
                }
                .controlSize(.small)
                .disabled(!logFileExists)
            }
            if let exportStatus {
                Text(exportStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("One reading every 10 seconds while Vitals runs, stored in a SQLite database (\(logSizeText)) at \(folderDisplayPath)/history. Export writes a timestamped CSV to \(folderDisplayPath)/exports. Open it in Numbers or Excel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                refresh &+= 1
            }
        }
    }

    private var logFileExists: Bool {
        FileManager.default.fileExists(atPath: DataHome.historyDatabaseFile.path)
    }

    private var folderDisplayPath: String {
        (DataHome.directory.path as NSString).abbreviatingWithTildeInPath
    }

    private var logSizeText: String {
        // Include WAL/SHM sidecars: recent rows sit in -wal until a checkpoint.
        let fm = FileManager.default
        let base = DataHome.historyDatabaseFile.path
        let paths = [base, base + "-wal", base + "-shm"]
        let total = paths.reduce(UInt64(0)) { sum, path in
            sum + ((try? fm.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0)
        }
        guard total > 0 else { return "no data yet" }
        return "currently " + ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    /// Same `HistoryExport` path as the History section, so the format matches.
    private func exportCSV() {
        exportStatus = "Exporting…"
        Task {
            let destination = await Task.detached(priority: .userInitiated) { HistoryExport.csv() }.value
            refresh &+= 1
            guard let destination else {
                exportStatus = "Nothing to export yet, or the export failed."
                return
            }
            exportStatus = "Exported \(destination.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }
}

// MARK: - Developer cards

struct DiagnosticLoggingCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsCard(title: "Diagnostic logging", symbol: "ant", tint: .teal) {
            settingsRow("Level") {
                Picker("", selection: $settings.diagnosticLogLevel) {
                    ForEach(LogLevel.settingChoices) { Text($0.settingLabel).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            settingsRow("Log file") {
                HStack(spacing: 8) {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([DataHome.logFile])
                    }
                    .disabled(!diagnosticLogExists)
                }
                .controlSize(.small)
            }
            Text("Records what the app's services are doing — separate from the readings log under Data. **Errors** logs only failures; **Normal** adds key events; **Verbose** traces everything (noisier). Written to \(folderDisplayPath)/logs/vitals.log.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var diagnosticLogExists: Bool {
        FileManager.default.fileExists(atPath: DataHome.logFile.path)
    }

    private var folderDisplayPath: String {
        (DataHome.directory.path as NSString).abbreviatingWithTildeInPath
    }
}

struct ErrorReportsCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsCard(title: "Crash reports", symbol: "exclamationmark.bubble", tint: .orange) {
            settingsRow("Send crash reports") {
                Toggle("", isOn: $settings.errorReportsEnabled)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            Text("Crashes, freezes and errors go to Sentry so they can be fixed, with your name, folders, file names and addresses removed first. Nothing about your readings is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ReportProblemCard: View {
    @State private var reporting = false

    var body: some View {
        SettingsCard(title: "Report a problem", symbol: "envelope.badge", tint: .blue) {
            settingsRow("Bug report") {
                Button("Email the Developer…") { reporting = true }
                    .controlSize(.small)
            }
            Text("Opens your mail app with a pre-filled message to the developer and reveals the log so you can attach it. Crashes from a previous run show up in the log automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $reporting) {
            ProblemReportView()
        }
    }
}
