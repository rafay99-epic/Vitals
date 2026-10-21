import SwiftUI

/// One searchable page of cards, grouped into sections across two columns.
/// Search filters cards by title and keywords.
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
                        // Each column is one continuous stack, so cards never strand a gap.
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
        .environment(\.settingsSearchQuery, query)
        // ⌘F focuses search while Settings is on screen.
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    /// Top inset clears the traffic-light strip, like the sidebar header.
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
        LazyVStack(alignment: .leading, spacing: 28) {
            ForEach(sections) { section in
                SettingsSectionView(section: section, query: query)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Hand-balanced by card weight so the columns end at roughly the same height.
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
    // `keywords` hold each card's control labels so search finds words not in the title.

    static let sections: [SettingsSectionModel] = [
        SettingsSectionModel(title: "General", cards: [
            .init(.readings, title: "Readings", keywords: "temperature unit celsius fahrenheit refresh interval chart history"),
            .init(.power, title: "Power", keywords: "battery ac sampling reduce low power mode"),
            .init(.appearance, title: "Appearance", keywords: "theme light dark system"),
            .init(.applications, title: "Applications", keywords: "launch at login startup hide dock icon menu bar only"),
        ]),
        SettingsSectionModel(title: "Menu bar", cards: [
            .init(.menuBar, title: "Menu bar", keywords: "status item readings icons text menubar"),
        ]),
        SettingsSectionModel(title: "Alerts", cards: [
            .init(.overheating, title: "Overheating", keywords: "hot threshold cpu temperature flame"),
            .init(.notifications, title: "Notifications", keywords: "notify overheat thermal pressure"),
        ]),
        SettingsSectionModel(title: "Updates", cards: [
            .init(.softwareUpdates, title: "Software updates", keywords: "version automatic check download install release"),
        ]),
        SettingsSectionModel(title: "Data", cards: [
            .init(.logging, title: "Logging", keywords: "log readings disk export csv history database"),
            .init(.cleanup, title: "Cleanup", keywords: "scan automatically caches"),
        ]),
        SettingsSectionModel(title: "Developer", cards: [
            .init(.diagnosticLogging, title: "Diagnostic logging", keywords: "level errors normal verbose log file"),
            .init(.reportProblem, title: "Report a problem", keywords: "bug report email developer crash"),
        ]),
        SettingsSectionModel(title: "About", showsAboutHero: true, cards: [
            .init(.company, title: "Company", keywords: "made by developer source code github"),
            .init(.license, title: "License", keywords: "gpl gnu open source free software"),
            .init(.acknowledgements, title: "Acknowledgements", keywords: "mole credit thanks"),
        ]),
    ]
}

// MARK: - Section model + layout

enum SettingsCardKind: Hashable {
    case readings, power, appearance, applications, menuBar, overheating, notifications
    case softwareUpdates, logging, cleanup, diagnosticLogging, reportProblem
    case company, license, acknowledgements

    @MainActor @ViewBuilder
    var card: some View {
        switch self {
        case .readings: ReadingsCard()
        case .power: PowerSettingsCard()
        case .appearance: AppearanceCard()
        case .applications: ApplicationCard()
        case .menuBar: MenuBarCard()
        case .overheating: OverheatingCard()
        case .notifications: NotificationsCard()
        case .softwareUpdates: SoftwareUpdatesCard()
        case .logging: LoggingCard()
        case .cleanup: CleanupCard()
        case .diagnosticLogging: DiagnosticLoggingCard()
        case .reportProblem: ReportProblemCard()
        case .company: CompanyCard()
        case .license: LicenseCard()
        case .acknowledgements: AcknowledgementsCard()
        }
    }
}

struct SettingsCardModel: Identifiable {
    let kind: SettingsCardKind
    let title: String
    let keywords: String
    var id: SettingsCardKind { kind }

    init(_ kind: SettingsCardKind, title: String, keywords: String) {
        self.kind = kind
        self.title = title
        self.keywords = keywords
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty
            || title.localizedCaseInsensitiveContains(query)
            || keywords.localizedCaseInsensitiveContains(query)
    }
}

struct SettingsSectionModel: Identifiable {
    var id: String { title }
    let title: String
    var showsAboutHero = false
    let cards: [SettingsCardModel]
}

/// A header rule, an optional prologue (the About hero), then its cards.
/// Hidden when search filters out all of its cards.
private struct SettingsSectionView: View {
    let section: SettingsSectionModel
    let query: String

    var body: some View {
        let visible = section.cards.filter { $0.matches(query) }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader
                if section.showsAboutHero { AboutHero() }
                ForEach(visible) { $0.kind.card }
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

/// Rounded design-language field in place of the system search control.
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
    /// The Settings search query, read by `HighlightLabel`.
    var settingsSearchQuery: String {
        get { self[SettingsSearchQueryKey.self] }
        set { self[SettingsSearchQueryKey.self] = newValue }
    }
}

/// Accents the first run matching the search query (2+ chars), so the user sees
/// why a card matched.
struct HighlightLabel: View {
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
