import SwiftUI
import AppKit

// MARK: - About

/// Icon, name, channel badge, and version above the About cards.
struct AboutHero: View {
    private var versionLine: String {
        var line: String
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? Updater.currentVersion
        if build == Updater.currentVersion {
            line = "Version \(Updater.currentVersion)"
        } else {
            line = "Version \(Updater.currentVersion) (build \(build))"
        }
        // Nightly and Dev builds stamp branch@sha.
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

struct CompanyCard: View {
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

struct LicenseCard: View {
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

struct AcknowledgementsCard: View {
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
