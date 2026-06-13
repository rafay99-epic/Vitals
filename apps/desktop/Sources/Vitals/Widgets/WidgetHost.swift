import SwiftUI

/// Shared chrome for every desktop widget: a frosted rounded card with a tinted
/// icon-tile header — the same visual language as the in-app cards
/// (`Views/Components.swift`), sized for a small floating panel.
struct WidgetCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.16))
                    )
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

/// The SwiftUI root hosted inside each floating panel: picks the card for the
/// widget kind and adds a hover close button + context menu. The cards read the
/// shared `VitalsModel` / `AppSettings` injected by `WidgetPanel`.
struct WidgetHost: View {
    let kind: WidgetKind
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            card
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
                .help("Close this widget")
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close \(kind.shortTitle)", systemImage: "xmark") { onClose() }
        }
    }

    @ViewBuilder
    private var card: some View {
        switch kind {
        case .cpu: CPUWidget()
        case .cpuUsage: CPUUsageWidget()
        case .memory: MemoryWidget()
        case .fan: FanWidget()
        case .storage: StorageWidget()
        case .combined: CombinedWidget()
        }
    }
}
