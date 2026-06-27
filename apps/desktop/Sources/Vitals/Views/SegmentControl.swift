import SwiftUI

/// The shared in-tab segmented control: a centered capsule with a spring-driven
/// sliding indicator, matching the header tab bar exactly so every switcher in
/// the app reads as one system. Used to pick a System sub-view (CPU/GPU/…) and an
/// Applications sub-view (Installed/Startup) — one component, never a copy.
///
/// `onSelect` fires before the selection animates, so a host can record the item
/// as visited (its kept-mounted view then stays alive for instant switch-back).
struct SegmentControl<Item: Identifiable & Equatable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let symbol: (Item) -> String
    var onSelect: (Item) -> Void = { _ in }
    @Namespace private var indicator

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(items) { button($0) }
            }
            .padding(3)
            .background(Capsule().fill(.quaternary.opacity(0.45)))
            Spacer(minLength: 0)
        }
    }

    private func button(_ item: Item) -> some View {
        let selected = selection == item
        return Button {
            onSelect(item)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                selection = item
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(item))
                    .font(.system(size: 11, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(title(item))
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if selected {
                Capsule()
                    .fill(.quaternary)
                    .matchedGeometryEffect(id: "segment", in: indicator)
            }
        }
        .accessibilityLabel(title(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title(item))
    }
}
