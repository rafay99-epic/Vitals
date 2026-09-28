import SwiftUI
import AppKit
import UserNotifications

/// Settings, the main window's last sidebar section: one searchable page of
/// titled cards, grouped into sections split across two continuous columns. The
/// search field live-filters cards by title and keywords.
struct SettingsView: View {
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                Group {
                    if anyMatch {
                        // Two columns of whole sections. Each column is one
                        // continuous vertical stack, so cards never strand a gap
                        // (the worst case is one column ending slightly lower at the
                        // very bottom — the section split below keeps them even).
                        HStack(alignment: .top, spacing: 24) {
                            column(leftSections)
                            column(rightSections)
                        }
                    } else {
                        noMatches
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Carry the query down so the building blocks can highlight matches.
        .environment(\.settingsSearchQuery, query)
        // ⌘F focuses search (Find), scoped to when Settings is on screen.
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    /// Page title + search, with a top inset that clears the traffic-light strip
    /// the way the sidebar header does.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
            Spacer(minLength: 12)
            SettingsSearchField(query: $query, focused: $searchFocused)
                .frame(maxWidth: 260)
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 16)
    }

    private func column(_ sections: [SettingsSectionModel]) -> some View {
        // Lazy: only sections near the viewport are built.
        LazyVStack(alignment: .leading, spacing: 28) {
            ForEach(sections) { section in
                SettingsSectionView(section: section, query: query)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Sections split across the two columns, hand-balanced by card weight so the
    /// columns end at roughly the same height.
    private var leftSections: [SettingsSectionModel] {
        Self.sections.filter { !Self.rightColumnTitles.contains($0.title) }
    }
    private var rightSections: [SettingsSectionModel] {
        Self.sections.filter { Self.rightColumnTitles.contains($0.title) }
    }
    private static let rightColumnTitles: Set<String> = ["Menu bar", "Alerts", "Updates"]

    private var anyMatch: Bool {
        query.isEmpty || Self.sections.contains { $0.cards.contains { $0.matches(query) } }
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No settings match “\(query)”")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - The section registry
    //
    // Listed in reading order; the page splits these sections across two columns
    // (see `rightColumnTitles`). Each card carries searchable `keywords` (its
    // controls' labels) so a query like "battery" or "log" surfaces the right cards
    // even when the word isn't in the title.

    static let sections: [SettingsSectionModel] = [
        SettingsSectionModel(title: "General", cards: [
            .init(title: "Readings", keywords: "temperature unit celsius fahrenheit refresh interval chart history",
                  view: AnyView(ReadingsCard())),
            .init(title: "Power", keywords: "battery ac sampling reduce low power mode",
                  view: AnyView(PowerSettingsCard())),
            .init(title: "Appearance", keywords: "theme light dark system",
                  view: AnyView(AppearanceCard())),
            .init(title: "Applications", keywords: "launch at login startup hide dock icon menu bar only",
                  view: AnyView(ApplicationCard())),
        ]),
        SettingsSectionModel(title: "Menu bar", cards: [
            .init(title: "Menu bar", keywords: "status item readings icons text menubar",
                  view: AnyView(MenuBarCard())),
        ]),
        SettingsSectionModel(title: "Alerts", cards: [
            .init(title: "Overheating", keywords: "hot threshold cpu temperature flame",
                  view: AnyView(OverheatingCard())),
            .init(title: "Notifications", keywords: "notify overheat thermal pressure",
                  view: AnyView(NotificationsCard())),
        ]),
        SettingsSectionModel(title: "Updates", cards: [
            .init(title: "Software updates", keywords: "version automatic check download install release",
                  view: AnyView(SoftwareUpdatesCard())),
        ]),
        SettingsSectionModel(title: "Data", cards: [
            .init(title: "Logging", keywords: "log readings disk export csv history database",
                  view: AnyView(LoggingCard())),
            .init(title: "Cleanup", keywords: "scan automatically caches",
                  view: AnyView(CleanupCard())),
        ]),
        SettingsSectionModel(title: "Developer", cards: [
            .init(title: "Diagnostic logging", keywords: "level errors normal verbose log file",
                  view: AnyView(DiagnosticLoggingCard())),
            .init(title: "Report a problem", keywords: "bug report email developer crash",
                  view: AnyView(ReportProblemCard())),
        ]),
        SettingsSectionModel(title: "About", prologue: AnyView(AboutHero()), cards: [
            .init(title: "Company", keywords: "made by developer source code github",
                  view: AnyView(CompanyCard())),
            .init(title: "License", keywords: "gpl gnu open source free software",
                  view: AnyView(LicenseCard())),
            .init(title: "Acknowledgements", keywords: "mole credit thanks",
                  view: AnyView(AcknowledgementsCard())),
        ]),
    ]
}

// MARK: - Section model + layout

struct SettingsCardModel: Identifiable {
    let id = UUID()
    let title: String
    let keywords: String
    let view: AnyView

    func matches(_ query: String) -> Bool {
        query.isEmpty
            || title.localizedCaseInsensitiveContains(query)
            || keywords.localizedCaseInsensitiveContains(query)
    }
}

struct SettingsSectionModel: Identifiable {
    var id: String { title }
    let title: String
    var prologue: AnyView? = nil
    let cards: [SettingsCardModel]
}

/// One section: a header rule, an optional full-width prologue (the About hero),
/// then its cards as a single continuous stack (the section *is* one page column),
/// so cards never strand a gap beside a taller sibling. Hidden entirely when the
/// search filters out all of its cards.
private struct SettingsSectionView: View {
    let section: SettingsSectionModel
    let query: String

    var body: some View {
        let visible = section.cards.filter { $0.matches(query) }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader
                if let prologue = section.prologue { prologue }
                // One continuous stack — the section *is* a column, so its cards
                // never leave a gap beside a taller sibling.
                ForEach(visible) { $0.view }
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Rectangle()
                .fill(.separator.opacity(0.5))
                .frame(height: 1)
        }
    }
}

/// The search box — design-language rounded field, not the dated system search
/// control. Live-filters as you type; the clear button resets it.
private struct SettingsSearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused.wrappedValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            TextField("Search settings…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(focused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.quaternary.opacity(0.3)))
        .overlay(
            Capsule().strokeBorder(
                focused.wrappedValue ? AnyShapeStyle(Color.accentColor.opacity(0.7)) : AnyShapeStyle(.separator.opacity(0.5)),
                lineWidth: 1
            )
        )
        .animation(.easeOut(duration: 0.12), value: focused.wrappedValue)
    }
}

// MARK: - Search match highlighting

private struct SettingsSearchQueryKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    /// The live Settings search query, read by the building-block labels so they
    /// can accent the matched substring wherever it appears.
    var settingsSearchQuery: String {
        get { self[SettingsSearchQueryKey.self] }
        set { self[SettingsSearchQueryKey.self] = newValue }
    }
}

/// A text label that accents the run matching the current search query — so when
/// a card surfaces from a search, the user sees *why* it matched. Base font/colour
/// come from the call site's modifiers; the matched run overrides to the accent.
private struct HighlightLabel: View {
    let text: String
    @Environment(\.settingsSearchQuery) private var query

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(highlighted)
    }

    private var highlighted: AttributedString {
        var string = AttributedString(text)
        guard query.count >= 2,
              let range = string.range(of: query, options: .caseInsensitive) else { return string }
        string[range].foregroundColor = .accentColor
        string[range].inlinePresentationIntent = .stronglyEmphasized
        return string
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
                HighlightLabel(title)
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
                HighlightLabel(label)
                    .font(.system(size: 12.5))
                if let caption {
                    HighlightLabel(caption)
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
                HighlightLabel(metric.label)
                    .font(.system(size: 12.5))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

private func settingsRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
    HStack {
        HighlightLabel(label)
            .font(.system(size: 12.5))
        Spacer()
        control()
    }
}

// MARK: - General cards

private struct ReadingsCard: View {
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

private struct PowerSettingsCard: View {
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

private struct AppearanceCard: View {
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

private struct ApplicationCard: View {
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

private struct MenuBarCard: View {
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

private struct CleanupCard: View {
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

private struct OverheatingCard: View {
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

private struct NotificationsCard: View {
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

// MARK: - Updates card

private struct SoftwareUpdatesCard: View {
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

private struct LoggingCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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
            Text("One reading every 10 seconds while Vitals runs, stored in a SQLite database (\(logSizeText)) at \(folderDisplayPath)/history. Export writes a timestamped CSV to \(folderDisplayPath)/exports — open it in Numbers or Excel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var logFileExists: Bool {
        FileManager.default.fileExists(atPath: DataHome.historyDatabaseFile.path)
    }

    private var folderDisplayPath: String {
        (DataHome.directory.path as NSString).abbreviatingWithTildeInPath
    }

    private var logSizeText: String {
        // Sum the database and its WAL/SHM sidecars — recent rows can sit in the
        // -wal file before a checkpoint, so the main file alone understates usage.
        let fm = FileManager.default
        let base = DataHome.historyDatabaseFile.path
        let paths = [base, base + "-wal", base + "-shm"]
        let total = paths.reduce(UInt64(0)) { sum, path in
            sum + ((try? fm.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0)
        }
        guard total > 0 else { return "no data yet" }
        return "currently " + ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    /// Exports the whole database as a timestamped CSV into the data home's
    /// `exports/` folder and reveals it — reusing `HistoryExport` so the format
    /// matches the History tab's export exactly.
    private func exportCSV() {
        Task.detached {
            guard let destination = HistoryExport.csv() else { return }
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        }
    }
}

// MARK: - Developer cards

private struct DiagnosticLoggingCard: View {
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

private struct ReportProblemCard: View {
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

// MARK: - About

/// The app identity hero at the top of the About section — icon, name + channel
/// badge, version, tagline. Full-width, centered, above the About cards.
private struct AboutHero: View {
    private var versionLine: String {
        var line: String
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? Updater.currentVersion
        if build == Updater.currentVersion {
            line = "Version \(Updater.currentVersion)"
        } else {
            line = "Version \(Updater.currentVersion) (build \(build))"
        }
        // Nightly and Dev builds stamp the exact branch@sha so you know what's running.
        if let info = Channel.buildInfo { line += " · \(info)" }
        return line
    }

    var body: some View {
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
    }
}

private struct CompanyCard: View {
    private static let company = "Syntax Lab Technology"
    private static let developer = "Abdul Rafay"
    private static let developerURL = URL(string: "https://rafay99.com")!
    private static let repoURL = URL(string: "https://github.com/\(Updater.repository)")!

    var body: some View {
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
    }
}

private struct LicenseCard: View {
    private static let licenseURL = URL(string: "https://github.com/\(Updater.repository)/blob/main/LICENSE")!

    var body: some View {
        SettingsCard(title: "License", symbol: "checkmark.seal", tint: .green) {
            settingsRow("License") {
                Link("GNU GPL v3.0", destination: Self.licenseURL)
                    .font(.system(size: 12.5))
            }
            Text("Vitals is free software: you may use, study, modify, and redistribute it under the same terms.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AcknowledgementsCard: View {
    private static let moleURL = URL(string: "https://github.com/tw93/mole")!

    var body: some View {
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
