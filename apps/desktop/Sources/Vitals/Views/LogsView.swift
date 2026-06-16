import SwiftUI
import AppKit

/// The in-app log console — a developer/diagnostics surface in the app's own
/// design language, not a terminal. Reads the live `LogStore` ring, filters by
/// level / category / search, and presents entries **grouped by day**, newest
/// first, each row showing time, level, category, message, source (file:line)
/// and any error detail. Display-only: it never mutates anything but its own
/// filter state and the in-memory view.
///
/// Not a main-window tab — it's a developer tool, so it lives in its own
/// window opened from Settings → Developer ("Open Log Console").
struct LogsView: View {
    @EnvironmentObject private var store: LogStore
    // Injected on the console window, used for the problem-report header.
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    @State private var minLevel: LogLevel = .debug
    @State private var category: LogCategory?
    @State private var search = ""
    @State private var reporting = false

    var body: some View {
        // Compute the filtered, grouped entries once per render — `days` builds
        // the filtered list internally, so deriving the count and the empty
        // check from it avoids re-filtering up to 2000 entries two more times.
        let groups = days
        let total = groups.reduce(0) { $0 + $1.entries.count }
        return VStack(spacing: 0) {
            controlBar(count: total)
            Divider().opacity(0.5)
            content(groups: groups)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $reporting) {
            ProblemReportView(model: model, settings: settings)
        }
    }

    // MARK: Filtering + day grouping

    /// Newest-first, with the level floor, category, and search text applied.
    private var filtered: [Log.Entry] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.entries.reversed().filter { entry in
            entry.level >= minLevel
                && (category == nil || entry.category == category)
                && (needle.isEmpty || entry.message.lowercased().contains(needle)
                    || entry.source.file.lowercased().contains(needle))
        }
    }

    /// Filtered entries grouped under day headings, newest day first.
    private var days: [(key: String, entries: [Log.Entry])] {
        var order: [String] = []
        var byDay: [String: [Log.Entry]] = [:]
        for entry in filtered {
            let day = Self.dayLabel(for: entry.time)
            if byDay[day] == nil { order.append(day); byDay[day] = [] }
            byDay[day]?.append(entry)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    // MARK: Control bar

    private func controlBar(count: Int) -> some View {
        HStack(spacing: 10) {
            levelMenu
            categoryMenu
            searchField
            Spacer(minLength: 8)
            Text("\(count) \(count == 1 ? "line" : "lines")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                reporting = true
            } label: {
                Label("Report…", systemImage: "envelope.badge")
            }
            .controlSize(.small)
            .help("Email these logs to the developer")
            Button("Clear") { store.clear() }
                .controlSize(.small)
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([DataHome.logFile])
            }
            .controlSize(.small)
            .help("Show vitals.log in the Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var levelMenu: some View {
        Menu {
            ForEach(LogLevel.allCases.filter { $0 != .off }) { level in
                Button {
                    minLevel = level
                } label: {
                    Label(level.label, systemImage: minLevel == level ? "checkmark" : "")
                }
            }
        } label: {
            filterLabel(symbol: "line.3.horizontal.decrease.circle", text: "≥ \(minLevel.label)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                category = nil
            } label: {
                Label("All categories", systemImage: category == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(LogCategory.allCases) { cat in
                Button {
                    category = cat
                } label: {
                    Label(cat.title, systemImage: category == cat ? "checkmark" : "")
                }
            }
        } label: {
            filterLabel(symbol: "square.grid.2x2", text: category?.title ?? "All")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func filterLabel(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 160)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    // MARK: Content

    @ViewBuilder
    private func content(groups: [(key: String, entries: [Log.Entry])]) -> some View {
        if groups.isEmpty {
            ScrollView {
                EmptyStateView(
                    symbol: store.entries.isEmpty ? "text.alignleft" : "line.3.horizontal.decrease.circle",
                    tint: .indigo,
                    title: store.entries.isEmpty ? "No log entries yet" : "Nothing matches",
                    message: store.entries.isEmpty
                        ? "Diagnostic events appear here as the app runs. Raise the level in Settings → Data for more detail."
                        : "No lines match the current level, category, or search. Widen the filters to see more."
                ) { EmptyView() }
                .padding(20)
            }
        } else {
            // List is lazy, so a couple thousand rows stay cheap to scroll.
            List {
                ForEach(groups, id: \.key) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            LogRow(entry: entry)
                                .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(day.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .textSelection(.enabled)
        }
    }

    /// "Today" / "Yesterday" / "Monday, June 16, 2026" for a day heading.
    static func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()
}

/// One console line: time, a coloured level badge, the category, the message,
/// the originating source, and — when present — the structured error detail.
private struct LogRow: View {
    let entry: Log.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.time, format: .dateTime.hour().minute().second())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)

            Text(entry.level.badge)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(levelColor)
                .frame(width: 30, alignment: .leading)

            Text(entry.category.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = entry.error {
                    Text(error.inline)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.9))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("\(entry.source.file):\(entry.source.line)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 130, alignment: .trailing)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.vertical, 1)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug:  return .secondary
        case .info:   return .teal
        case .notice: return .blue
        case .error:  return .orange
        case .fault:  return .red
        case .off:    return .secondary
        }
    }
}
