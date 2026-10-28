import SwiftUI

// MARK: - Section scaffold

/// A monitoring section's scrolling canvas. Lazy, so off-screen cards cost
/// nothing until scrolled to.
struct MetricScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, content: content)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Cards

/// A titled card. `accessory` sits at the trailing end of the title row (a "See all").
struct SectionCard<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                accessory
            }
            content
        }
        // maxHeight lets paired cards in a row share the row's height. In a vertical
        // scroll the proposed height is the ideal, so it doesn't stretch.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .cardBackground()
    }
}

extension SectionCard where Accessory == EmptyView {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, content: content) { EmptyView() }
    }
}

struct CardPlaceholder: View {
    let text: String
    var minHeight: CGFloat = 60

    init(_ text: String, minHeight: CGFloat = 60) {
        self.text = text
        self.minHeight = minHeight
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

extension View {
    /// The shared card chrome: radius 12, control fill, hairline border.
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        )
    }

    func insetCard(fill: Double = 0.3, border: Double = 0.5, cornerRadius: CGFloat = 12, selected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(
            shape.fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(fill)))
        )
        .overlay(
            shape.strokeBorder(
                selected ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator.opacity(border)),
                lineWidth: 1
            )
        )
    }
}
