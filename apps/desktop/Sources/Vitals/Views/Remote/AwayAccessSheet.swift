import SwiftUI
import AppKit

/// Guided Tailscale setup. Shows only the step the gateway reports as next, with
/// one button; the gateway re-checks Tailscale itself, so the sheet advances as
/// status updates arrive.
struct AwayAccessSheet: View {
    @Environment(RemoteModel.self) private var remote
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let setup = remote.status?.setup {
                content(setup)
            } else {
                ProgressView().frame(maxWidth: .infinity)
                Button("Close") { isPresented = false }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 420, alignment: .leading)
    }

    @ViewBuilder
    private func content(_ setup: TailscaleSetup) -> some View {
        let step = setup.step
        let finished = step.finished(ownerLogin: remote.status?.ownerLogin)
        if let number = step.number {
            Text("step \(number) of 4").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        Text(step.title).font(.title2.weight(.semibold))
        Text(step == .external ? remote.status?.detail ?? "" : step.message)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        if !finished.isEmpty {
            Text(finished.map { "✓ \($0)" }.joined(separator: " · "))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        if step == .https, setup.url == nil {
            Text("Waiting for Tailscale").font(.callout).foregroundStyle(.orange)
        }
        HStack {
            if step != .ready, step != .external {
                Button("Close") { isPresented = false }.keyboardShortcut(.cancelAction)
            }
            Spacer()
            Button(step.action) { perform(setup) }
                .keyboardShortcut(.defaultAction)
                .disabled(step == .https && setup.url == nil)
        }
        .padding(.top, 6)
    }

    private func perform(_ setup: TailscaleSetup) {
        switch setup.step {
        case .install: open("https://tailscale.com/download/mac")
        case .start, .signin: openTailscale()
        case .magicdns: open(setup.url ?? "https://login.tailscale.com/admin/dns")
        case .https: setup.url.map(open)
        case .ready, .external: isPresented = false
        }
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The standalone build first, then the App Store one. Neither found means
    /// the status is stale; the download page is the useful fallback.
    private func openTailscale() {
        let app = ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"]
            .lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
        guard let app else { return open("https://tailscale.com/download/mac") }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

extension TailscaleSetup.Step {
    var title: String {
        switch self {
        case .install: return "Install Tailscale."
        case .start: return "Open Tailscale."
        case .signin: return "Sign in to Tailscale."
        case .magicdns: return "Turn on MagicDNS."
        case .https: return "Allow HTTPS for Vitals."
        case .ready: return "Away access is on."
        case .external: return "Managed outside Vitals."
        }
    }

    var message: String {
        switch self {
        case .install: return "Tailscale gives your phone a private path to this Mac from anywhere."
        case .start: return "Tailscale is installed but not running."
        case .signin: return "Use the same account you'll use on your phone."
        case .magicdns: return "It gives this Mac a stable name on your tailnet."
        case .https: return "Tailscale asks once before it serves Vitals on your tailnet. It opens in your browser."
        case .ready: return "Your phone can reach this Mac from anywhere."
        case .external: return ""
        }
    }

    var action: String {
        switch self {
        case .install: return "Get Tailscale"
        case .start, .signin: return "Open Tailscale"
        case .magicdns: return "Open DNS settings"
        case .https: return "Allow in Tailscale"
        case .ready, .external: return "Done"
        }
    }

    /// Steps already behind this one, for the collapsed "✓ installed · ✓ signed in" line.
    func finished(ownerLogin: String?) -> [String] {
        let signedIn = ownerLogin.map { "signed in as \($0)" } ?? "signed in"
        switch self {
        case .install, .external: return []
        case .start, .signin: return ["installed"]
        case .magicdns: return ["installed", signedIn]
        case .https: return ["installed", signedIn, "MagicDNS"]
        case .ready: return ["installed", signedIn, "MagicDNS", "HTTPS"]
        }
    }
}
