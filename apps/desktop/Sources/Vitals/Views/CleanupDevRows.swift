import SwiftUI

// MARK: Developer rows

struct DevProjectRow: View {
    let project: DevJunkScanner.Project
    let selected: Bool
    let isScanning: Bool
    let selectedArtifacts: Set<URL>
    let toggleProject: () -> Void
    let toggleArtifact: (URL) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                ForEach(project.artifacts) { artifact in
                    Divider()
                        .opacity(0.35)
                        .padding(.leading, 47)
                    DevArtifactRow(
                        artifact: artifact,
                        selected: selectedArtifacts.contains(artifact.url),
                        isScanning: isScanning,
                        toggle: { toggleArtifact(artifact.url) }
                    )
                }
            }
        }
        .insetCard(selected: selected)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { toggleProject() } label: {
                HStack(spacing: 11) {
                    IconTile(symbol: "folder.badge.gearshape", tint: .orange, size: 28, font: .system(size: 13, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(abbreviatedPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(activeCaption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 10)
                    sizeLabel
                    SelectionMark(selected: selected)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Hide artifacts" : "Show \(project.artifacts.count) artifact\(project.artifacts.count == 1 ? "" : "s")")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if isScanning && project.totalBytes == 0 {
            ProgressView()
                .controlSize(.small)
                .frame(width: 74, alignment: .trailing)
        } else {
            Text(formatBytes(project.totalBytes))
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 74, alignment: .trailing)
        }
    }

    private var abbreviatedPath: String {
        (project.root.path as NSString).abbreviatingWithTildeInPath
    }

    private var activeCaption: String {
        guard let date = project.lastActive else { return "activity unknown" }
        return "active \(date.formatted(.relative(presentation: .named)))"
    }
}

private struct DevArtifactRow: View {
    let artifact: DevJunkScanner.Artifact
    let selected: Bool
    let isScanning: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Text(artifact.kindName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary.opacity(0.5)))
                Spacer(minLength: 8)
                if isScanning && artifact.sizeBytes == 0 {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(formatBytes(artifact.sizeBytes))
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                }
                SelectionMark(selected: selected, size: 14)
            }
            .padding(.leading, 47)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
