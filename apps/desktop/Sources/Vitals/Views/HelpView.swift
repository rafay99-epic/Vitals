import SwiftUI

/// In-app help: what every reading means and how the careful parts (fan
/// control, uninstalling, cleanup) behave. Reachable from the menu-bar
/// panel and the Help menu.
struct HelpView: View {
    private struct Topic: Identifiable {
        let symbol: String
        let tint: Color
        let title: String
        let body: String
        var id: String { title }
    }

    private static let topics: [Topic] = [
        Topic(
            symbol: "gauge.with.dots.needle.50percent",
            tint: .green,
            title: "Dashboard",
            body: "Every number is a real reading from your hardware. Average CPU comes from the die temperature sensors, Hottest Core is the single warmest one, and Thermal Pressure is macOS's own throttling signal. When the fan shows 0 rpm, it genuinely isn't spinning."
        ),
        Topic(
            symbol: "cpu",
            tint: .blue,
            title: "System",
            body: "Every hardware deep-dive lives here behind one filter: CPU, GPU, Memory, Battery, Sensors (all temperatures, the fans and their control, and drive health), Processes, and History. Pick a segment to change the view — the window never resizes. The Dashboard shows the headlines; this is where you go for detail."
        ),
        Topic(
            symbol: "menubar.rectangle",
            tint: .blue,
            title: "Menu bar",
            body: "The menu bar item shows your average CPU temperature (configurable in Settings → General). Click it for live sparklines, memory and swap, and quick fan presets without opening the main window."
        ),
        Topic(
            symbol: "fan",
            tint: .cyan,
            title: "Fan control",
            body: "Enabling fan control installs a small helper once (one administrator password). Speeds are always clamped to the manufacturer's rated range, macOS's thermal protection stays active underneath, and Auto hands control back to the system. Disable… in the Fans card removes the helper completely."
        ),
        Topic(
            symbol: "square.grid.2x2",
            tint: .purple,
            title: "Applications",
            body: "Two segments: Installed and Startup. Uninstalling moves the app and its leftover files (caches, preferences, containers, launch agents) to the Trash — nothing is deleted permanently, so you can always recover from the Finder. System apps and Apple software are never listed. Startup shows everything that launches itself at login; you can disable or remove your own items, while Apple's stay read-only."
        ),
        Topic(
            symbol: "sparkles",
            tint: .orange,
            title: "Cleanup",
            body: "Four pages. Quick and Deep offer only regenerable data — build products, package caches, app caches, and logs that apps rebuild automatically; documents and settings are never touched. Developer lists per-project build junk (node_modules, target, Pods, DerivedData) you can clear a project at a time. Files reviews your large and old files and moves the ones you pick to the Trash — recoverable from the Finder. Emptying the Trash and deleting build junk are permanent, and each confirmation says so."
        ),
        Topic(
            symbol: "internaldrive",
            tint: .blue,
            title: "Storage",
            body: "See how full your disk is and where the space went — Applications, your home folder, and both Libraries, measured as real on-disk bytes. Press Analyze to scan (it walks the disk, so it waits for you), Stop any time, and drill into the largest folders and files. For a complete report, grant Full Disk Access when prompted — without it Vitals still works but skips protected folders. Storage only reads: it never deletes. Reclaiming space lives in Cleanup."
        ),
        Topic(
            symbol: "bell.badge",
            tint: .red,
            title: "Alerts",
            body: "Vitals can notify you when the CPU stays above your chosen threshold for two minutes, or when macOS raises thermal pressure to Serious. Configure both in Settings → Alerts."
        ),
        Topic(
            symbol: "keyboard",
            tint: .teal,
            title: "Shortcuts",
            body: "⌘1 Overview · ⌘2–⌘9 the Monitor sections (CPU through History) · ⌥⌘1–⌥⌘4 the Maintain sections (Storage, Cleanup, Applications, Login Items) · ⌘, Settings. The sidebar header drags the window."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Vitals Help")
                            .font(.system(size: 18, weight: .semibold))
                        Text("How the readings and tools work")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)

                ForEach(Self.topics) { topic in
                    topicCard(topic)
                }

                HStack(spacing: 16) {
                    Link("Report an issue", destination: URL(string: "https://github.com/\(Updater.repository)/issues")!)
                    Link("Source code", destination: URL(string: "https://github.com/\(Updater.repository)")!)
                    Link("rafay99.com", destination: URL(string: "https://rafay99.com")!)
                    Spacer()
                    Text("Version \(Updater.currentVersion)")
                        .foregroundStyle(.tertiary)
                }
                .font(.callout)
                .padding(.top, 6)
            }
            .padding(20)
        }
        .frame(width: 520, height: 620)
    }

    private func topicCard(_ topic: Topic) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: topic.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(topic.tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(topic.tint.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(topic.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        )
    }
}
