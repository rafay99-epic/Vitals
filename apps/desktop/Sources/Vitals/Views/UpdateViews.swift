import SwiftUI

/// The sidebar header's update button: a download icon when an update is
/// available or downloaded (one click installs), a spinner while downloading or
/// installing, nothing when up to date.
struct HeaderUpdateButton: View {
    @Environment(Updater.self) private var updater
    @State private var hovered = false

    var body: some View {
        switch updater.status {
        case .available(let release):
            installButton(tint: .blue, help: "Install \(Channel.current.displayName) \(release.displayVersion)") {
                await updater.downloadAndInstall()
            }
        case .readyToInstall(let release):
            installButton(tint: .green, help: "Install \(Channel.current.displayName) \(release.displayVersion) — downloaded and ready") {
                await updater.installPending()
            }
        case .downloading:
            spinner.help("Downloading update…")
        case .installing:
            spinner.help("Installing — Vitals will relaunch in a moment")
        default:
            EmptyView()
        }
    }

    private func installButton(tint: Color, help: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(hovered ? 0.22 : 0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { hovered = hovering }
        }
        .help(help)
    }

    private var spinner: some View {
        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 26, height: 26)
    }
}

/// Shown at the top of the dashboard while an update is available or installing.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        switch updater.status {
        case .available(let release):
            banner {
                Label("Vitals \(release.displayVersion) is available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("You're on \(Updater.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install Update") {
                    Task { await updater.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .readyToInstall(let release):
            banner {
                Label("Vitals \(release.displayVersion) is ready to install", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                Text("Downloaded in the background")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install & Relaunch") {
                    Task { await updater.installPending() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .downloading:
            banner {
                Label("Downloading update…", systemImage: "arrow.down.circle")
                Spacer()
                ProgressView().controlSize(.small)
            }
        case .installing:
            banner {
                Label("Installing — Vitals will relaunch in a moment", systemImage: "gearshape.arrow.triangle.2.circlepath")
                Spacer()
                ProgressView().controlSize(.small)
            }
        default:
            EmptyView()
        }
    }

    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .font(.callout)
            .padding(12)
            .cardBackground()
    }
}
