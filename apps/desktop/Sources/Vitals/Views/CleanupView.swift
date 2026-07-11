import SwiftUI

/// The Cleanup tab: five pages behind one segmented picker — the classic Quick
/// and Deep cache sweeps, per-project Developer junk, a Large-&-Old Files review,
/// and a content-verified Duplicates finder. Pages swap **in place** (the
/// performance rule: navigation never changes window geometry); each page keeps
/// its own hero, scroll, and footer.
struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    /// True only while Cleanup is the visible tab; the view stays mounted.
    var isActive: Bool
    /// Persisted so the chosen page sticks across launches.
    @AppStorage("cleanupPage") private var page: CleanupPage = .quick
    /// The old two-value depth switch — migrated once into `page` so a user who
    /// left Cleanup on Deep lands on the Deep page.
    @AppStorage("cleanupDepth") private var legacyDepth: CleanDepth = .quick
    @AppStorage("cleanupPageMigrated") private var pageMigrated = false

    var body: some View {
        VStack(spacing: 0) {
            picker
            Divider()
                .opacity(0.5)
            ZStack {
                switch page {
                case .quick:
                    CleanupClassicPage(model: model, isActive: isActive, depth: .quick)
                        .transition(.opacity)
                case .deep:
                    CleanupClassicPage(model: model, isActive: isActive, depth: .deep)
                        .transition(.opacity)
                case .developer:
                    CleanupDeveloperPage(model: model)
                        .transition(.opacity)
                case .files:
                    CleanupFilesPage(model: model)
                        .transition(.opacity)
                case .duplicates:
                    CleanupDuplicatesPage(model: model)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: page)
        }
        .onAppear {
            guard !pageMigrated else { return }
            if legacyDepth == .deep { page = .deep }
            pageMigrated = true
        }
    }

    private var picker: some View {
        HStack {
            // A pull-down menu, not a segment row: the mode label shows the current
            // page with its icon, and the list scales without crowding the bar
            // (matches the History metric picker).
            Picker(selection: $page) {
                ForEach(CleanupPage.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            } label: {
                Label(page.title, systemImage: page.symbol)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(model.isCleaning || model.isDevCleaning || model.isFilesCleaning || model.isDupCleaning)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Quick / Deep page

/// The classic cache sweep — today's Cleanup behavior, one page per depth. The
/// old in-hero depth picker is gone; `depth` is fixed and the four-way page
/// picker above chooses it. Quick stays in the user domain (no password); Deep
/// adds age-gated system categories that need one administrator prompt.
private struct CleanupClassicPage: View {
    @ObservedObject var model: CleanupModel
    /// True only while Cleanup is the visible tab.
    var isActive: Bool
    let depth: CleanDepth
    @EnvironmentObject private var settings: AppSettings
    @State private var confirming = false
    @State private var confirmingDestructive = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.hasRun {
                        idlePrompt
                    } else if !model.isScanning && model.totalBytes == 0 {
                        allClean
                    } else {
                        grid
                    }
                }
                .padding(20)
            }
            if let count = model.localSnapshots, model.hasRun {
                snapshotNote(count)
            }
            Divider()
                .opacity(0.5)
            footer
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            // Mounting this page (or re-activating the tab) measures for its
            // depth: if a scan already ran at the other depth, re-measure for
            // this one; otherwise honor auto-scan on the first run.
            if model.hasRun && model.depth != depth {
                model.scan(depth: depth)
            } else if settings.autoScanCleanup && !model.hasRun {
                model.scan(depth: depth)
            }
        }
        .confirmationDialog(
            "Clean \(formatBytes(model.selectedBytes))?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            // Anything irreversible gets a second, explicit confirmation that
            // names exactly what will be destroyed; otherwise clean straight away.
            Button(model.selectionNeedsAdmin ? "Deep Clean" : "Clean", role: .destructive) {
                if model.selectedDestructiveCategories.isEmpty {
                    model.clean()
                } else {
                    confirmingDestructive = true
                }
            }
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog(
            destructiveTitle,
            isPresented: $confirmingDestructive,
            titleVisibility: .visible
        ) {
            Button(destructiveButtonLabel, role: .destructive) { model.clean() }
        } message: {
            Text(destructiveMessage)
        }
        .alert(
            "Cleanup finished",
            isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.dismissResult() } }),
            presenting: model.lastResult
        ) { _ in
            Button("OK") { model.dismissResult() }
        } message: { result in
            if result.failures.isEmpty {
                Text("Freed \(formatBytes(result.freedBytes)) (\(result.removedItems) items)\(result.usedAdmin ? " — protected items included." : ".")")
            } else {
                Text("Freed \(formatBytes(result.freedBytes)). \(result.failures.count) items couldn't be removed (in use or protected).")
            }
        }
        .alert(
            "Couldn't finish deep clean",
            isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.dismissError() } }),
            presenting: model.lastError
        ) { _ in
            Button("OK") { model.dismissError() }
        } message: { message in
            Text(message)
        }
    }

    private var confirmationMessage: String {
        var lines = "Selected caches and logs are deleted — apps rebuild them automatically."
        if model.selected.contains(.trash) {
            lines += " Emptying the Trash is permanent."
        }
        if model.selectionNeedsAdmin {
            lines += " System files need your administrator password; only files older than the retention window are removed."
        }
        return lines
    }

    /// Destructive categories that end up in the Trash (recoverable) rather
    /// than deleted in place — split from the permanent ones so the second
    /// confirmation never overstates what's about to happen.
    private var destructiveTrashCategories: [CleanupCategory] {
        model.selectedDestructiveCategories.filter { $0.kind.movesToTrash }
    }

    private var destructivePermanentCategories: [CleanupCategory] {
        model.selectedDestructiveCategories.filter { !$0.kind.movesToTrash }
    }

    private var destructiveTitle: String {
        let size = formatBytes(model.selectedDestructiveCategories.reduce(0) { $0 + $1.sizeBytes })
        return destructivePermanentCategories.isEmpty ? "Move \(size) to the Trash?" : "Permanently delete \(size)?"
    }

    private var destructiveButtonLabel: String {
        destructivePermanentCategories.isEmpty ? "Move to Trash" : "Permanently Delete"
    }

    private var destructiveMessage: String {
        func names(_ categories: [CleanupCategory]) -> String {
            categories
                .map { "\($0.kind.title) (\(formatBytes($0.sizeBytes)))" }
                .joined(separator: ", ")
        }
        let permanentNames = names(destructivePermanentCategories)
        let trashNames = names(destructiveTrashCategories)
        if destructivePermanentCategories.isEmpty {
            return "This moves \(trashNames) to the Trash — recoverable until you empty it."
        }
        if destructiveTrashCategories.isEmpty {
            return "This permanently deletes \(permanentNames). It is not regenerable and can't be recovered — make sure you have another copy. This can't be undone."
        }
        return "This permanently deletes \(permanentNames) — not regenerable and can't be recovered, make sure you have another copy. \(trashNames) is moved to the Trash instead — recoverable until you empty it."
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(heroValue)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(heroSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                Button(role: .cancel) {
                    model.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
                .help("Stop scanning")
            } else {
                Button {
                    model.scan(depth: depth)
                } label: {
                    Label(model.hasRun ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isCleaning)
                .help("Measure what's reclaimable")
            }
        }
    }

    private var heroValue: String {
        if model.totalBytes > 0 { return formatBytes(model.totalBytes) }
        if model.isScanning { return "Scanning…" }
        return model.hasRun ? "All clean" : "—"
    }

    private var heroSubtitle: String {
        if model.isScanning { return "measuring \(depth == .deep ? "user and system" : "user") junk" }
        let populated = model.categories.filter { $0.sizeBytes > 0 }.count
        if model.totalBytes > 0 {
            return "reclaimable across \(populated) categories — all of it regenerable"
        }
        return model.hasRun ? "nothing worth reclaiming right now" : "scan to see what's reclaimable"
    }

    // MARK: Idle prompt

    private var idlePrompt: some View {
        EmptyStateView(
            symbol: "sparkles",
            tint: .orange,
            title: "Free up space safely",
            message: "Vitals finds regenerable junk — developer and browser caches, app caches, logs, device firmware, and the Trash. Browser history, cookies and logins are never touched. Quick stays in your home folder; Deep adds age-gated system files (one admin prompt) and, only if you choose, iOS backups — those need a second confirmation. Auto-scan is in Settings.",
            hints: [
                .init(symbol: "shippingbox", label: "Caches"),
                .init(symbol: "doc.text", label: "Logs"),
                .init(symbol: "lock", label: "System · Deep"),
            ]
        ) {
            Button { model.scan(depth: depth) } label: {
                Label("Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var allClean: some View {
        EmptyStateView(
            symbol: "checkmark.seal.fill",
            tint: .green,
            title: "All clean",
            message: "Nothing worth reclaiming right now — your caches, logs, and Trash are already tidy."
        ) {
            Button { model.scan(depth: depth) } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
        }
    }

    // MARK: Category grid

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(model.categories) { category in
                CategoryCard(
                    category: category,
                    isScanning: model.isScanning,
                    isSelected: model.selected.contains(category.kind)
                ) {
                    if model.selected.contains(category.kind) {
                        model.selected.remove(category.kind)
                    } else {
                        model.selected.insert(category.kind)
                    }
                }
            }
        }
    }

    // MARK: Snapshot note (report-only)

    private func snapshotNote(_ count: Int) -> some View {
        Label(
            "\(count) Time Machine local snapshot\(count == 1 ? "" : "s") on this disk — macOS frees these automatically under disk pressure. Review with “tmutil listlocalsnapshots /”.",
            systemImage: "clock.arrow.2.circlepath"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .fixedSize(horizontal: false, vertical: true)
        .help("Reported like Mole. Vitals doesn't delete snapshots — the system manages them.")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label(footerNote, systemImage: footerSymbol)
                .font(.caption)
                .foregroundStyle(model.selectedDestructiveCategories.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
            Spacer()
            if !model.selected.isEmpty {
                Text("\(model.selected.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                confirming = true
            } label: {
                if model.isCleaning {
                    Label("Cleaning…", systemImage: "sparkles")
                } else {
                    Label(cleanButtonTitle, systemImage: model.selectionNeedsAdmin ? "lock.fill" : "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selected.isEmpty || model.isCleaning || model.selectedBytes == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var footerNote: String {
        if !model.selectedDestructiveCategories.isEmpty {
            return "Includes permanent, non-recoverable items — you'll confirm again before they're deleted."
        }
        return model.selectionNeedsAdmin
            ? "System files removed with your permission — only old, regenerable data."
            : "Only regenerable data — documents and settings are never touched."
    }

    private var footerSymbol: String {
        if !model.selectedDestructiveCategories.isEmpty { return "exclamationmark.triangle.fill" }
        return model.selectionNeedsAdmin ? "lock.shield" : "checkmark.shield"
    }

    private var cleanButtonTitle: String {
        if model.selectedBytes == 0 { return "Clean" }
        let size = formatBytes(model.selectedBytes)
        return model.selectionNeedsAdmin ? "Deep Clean \(size)…" : "Clean \(size)"
    }
}

// MARK: - Category card

private extension CleanupCategory.Kind {
    var tint: Color {
        switch self {
        case .xcode: return .blue
        case .devCaches: return .orange
        case .deviceSupport: return .cyan
        case .browserCaches: return .green
        case .deviceFirmware: return .indigo
        case .deviceBackups: return .red
        case .homebrew: return .yellow
        case .appCaches: return .purple
        case .logs: return .teal
        case .trash: return .red
        case .recentItems: return .indigo
        case .aiCaches: return .purple
        case .aiHistory: return .pink
        case .systemCaches: return .gray
        case .systemLogs: return .mint
        case .crashReports: return .red
        case .systemTemp: return .brown
        case .gpuCaches: return .pink
        }
    }
}

private struct CategoryCard: View {
    let category: CleanupCategory
    let isScanning: Bool
    let isSelected: Bool
    let toggle: () -> Void

    /// Disabled only once a scan has settled with nothing to remove.
    private var hasNothing: Bool { !isScanning && category.sizeBytes == 0 }

    private var emptyLabel: String {
        if category.kind.requiresAdmin { return "Nothing old enough" }
        return category.items.isEmpty ? "Nothing found" : "Empty"
    }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: category.kind.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(category.kind.tint)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(category.kind.tint.opacity(0.14))
                        )
                    Text(category.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    if category.kind.requiresAdmin {
                        Image(systemName: "lock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Removing these needs administrator rights")
                    }
                    if category.kind.isDestructive {
                        if category.kind.movesToTrash {
                            Text("TO TRASH")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(.orange.opacity(0.16)))
                                .foregroundStyle(.orange)
                                .help("Moved to the Trash — recoverable until you empty it")
                        } else {
                            Text("PERMANENT")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(.red.opacity(0.16)))
                                .foregroundStyle(.red)
                                .help("Not regenerable — deleted permanently and can't be recovered")
                        }
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                }

                Text(category.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)

                HStack(alignment: .firstTextBaseline) {
                    if isScanning && category.sizeBytes == 0 {
                        ProgressView()
                            .controlSize(.small)
                    } else if category.sizeBytes == 0 {
                        Text(emptyLabel)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(formatBytes(category.sizeBytes))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if category.sizeBytes > 0 {
                        Text("\(category.items.count) item\(category.items.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator.opacity(0.5)),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(hasNothing)
        .opacity(hasNothing ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
