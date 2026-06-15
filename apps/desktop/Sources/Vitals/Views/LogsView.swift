import SwiftUI
import AppKit

/// The in-app log console — a developer/diagnostics surface in the app's own
/// design language, not a terminal. Reads the live `LogStore` ring, filters by
/// level / category / search text, and shows newest-first. Display-only: it
/// never mutates anything but its own filter state and the in-memory view.
///
/// Hidden by default (see `AppSettings` default `hiddenTabs`); a user or support
/// session turns the "Logs" tab on in Settings → Tabs.
struct LogsView: View {
    @EnvironmentObject private var store: LogStore
    let isActive: Bool

    @State private var minLevel: LogLevel = .debug
    @State private var category: LogCategory?
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider().opacity(0.5)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Filtering

    /// Newest-first, with the level floor, category, and search text applied.
    private var filtered: [Log.Entry] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.entries.reversed().filter { entry in
            entry.level >= minLevel
                && (category == nil || entry.category == category)
                && (needle.isEmpty || entry.message.lowercased().contains(needle))
        }
    }

    // MARK: Control bar

    private var controlBar: some View {
        HStack(spacing: 10) {
            levelMenu
            categoryMenu
            searchField
            Spacer(minLength: 8)
            Text("\(filtered.count) \(filtered.count == 1 ? "line" : "lines")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
    private var content: some View {
        if filtered.isEmpty {
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
            List(filtered) { entry in
                LogRow(entry: entry)
                    .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .textSelection(.enabled)
        }
    }
}

/// One console line: time, a coloured level badge, the category, and the message.
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

            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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
