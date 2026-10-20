import SwiftUI

// MARK: - Quick / Deep page

/// The cache sweep, one page per depth. Quick stays in the user domain (no
/// password); Deep adds age-gated system categories behind one admin prompt.
struct CleanupClassicPage: View {
    @Bindable var model: CleanupModel
    let depth: CleanDepth
    @Environment(AppSettings.self) private var settings
    @State private var confirming = false
    @State private var confirmingDestructive = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.hasRun || (!model.isScanning && !model.scanComplete && model.totalBytes == 0) {
                        idlePrompt
                    } else if model.scanComplete && model.totalBytes == 0 {
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
        .onAppear {
            // If a scan already ran at the other depth, re-measure for this one;
            // otherwise honor auto-scan on the first run.
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
            Button("Permanently Delete", role: .destructive) { model.clean() }
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
        var lines = "The selected items are removed. Documents, settings and files outside these categories are left untouched."
        if model.selected.contains(.trash) {
            lines += " Emptying the Trash is permanent."
        }
        if model.selectionNeedsAdmin {
            lines += " System files need your administrator password; only files older than the retention window are removed."
        }
        return lines
    }

    private var destructiveTitle: String {
        "Permanently delete \(formatBytes(model.selectedDestructiveCategories.reduce(0) { $0 + $1.sizeBytes }))?"
    }

    private var destructiveMessage: String {
        let names = model.selectedDestructiveCategories
            .map { "\($0.kind.title) (\(formatBytes($0.sizeBytes)))" }
            .joined(separator: ", ")
        return "This permanently deletes \(names). It is not regenerable and can't be recovered, so make sure you have another copy. This can't be undone."
    }

    // MARK: Hero

    private var hero: some View {
        PageHero(value: heroValue, subtitle: heroSubtitle) {
            ScanButtons(
                isScanning: model.isScanning,
                hasRun: model.hasRun,
                disabled: model.isCleaning,
                help: "Measure what's reclaimable",
                scan: { model.scan(depth: depth) },
                stop: { model.cancelScan() }
            )
        }
    }

    private var heroValue: String {
        if model.totalBytes > 0 { return formatBytes(model.totalBytes) }
        if model.isScanning { return "Scanning…" }
        return model.scanComplete ? "All clean" : "—"
    }

    private var heroSubtitle: String {
        if model.isScanning { return "measuring \(depth == .deep ? "user and system" : "user") junk" }
        let populated = model.categories.filter { $0.sizeBytes > 0 }.count
        if model.totalBytes > 0 {
            return "reclaimable across \(populated) categories"
        }
        return model.scanComplete ? "nothing worth reclaiming right now" : "scan to see what's reclaimable"
    }

    // MARK: Idle prompt

    private var idlePrompt: some View {
        EmptyStateView(
            symbol: "sparkles",
            tint: .orange,
            title: "Free up space safely",
            message: "Vitals finds regenerable junk — developer and browser caches, app caches, logs, device firmware, and the Trash. Browser history, cookies and logins are never touched. Quick stays in your home folder; Deep adds age-gated system files (with your administrator password) and, only if you choose, iOS backups, which need a second confirmation. Auto-scan is in Settings.",
            hints: [
                .init(symbol: "shippingbox", label: "Caches"),
                .init(symbol: "doc.text", label: "Logs"),
                .init(symbol: "lock", label: "System · Deep")
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
            .disabled(model.selected.isEmpty || model.isCleaning || model.isScanning || model.selectedBytes == 0)
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
