import SwiftUI

/// A short hint chip shown under an empty state's copy.
struct EmptyStateHint: Identifiable {
    let symbol: String
    let label: String
    var id: String { label }
}

/// The shared empty/idle state: icon tile, headline, supporting copy,
/// optional hint chips, and the primary action.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var hints: [EmptyStateHint] = []
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !hints.isEmpty {
                HStack(spacing: 8) {
                    ForEach(hints) { hint in
                        HStack(spacing: 5) {
                            Image(systemName: hint.symbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(hint.label)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.quaternary.opacity(0.5)))
                    }
                }
                .padding(.top, 2)
            }
            actions()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
        .cardBackground()
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 92, height: 92)
                .blur(radius: 22)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, tint: Color, title: String, message: String, hints: [EmptyStateHint] = []) {
        self.init(symbol: symbol, tint: tint, title: title, message: message, hints: hints) { EmptyView() }
    }
}

/// The loading sibling of `EmptyStateView`: same chrome, a spinner in place
/// of the icon tile.
struct LoadingStateView: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .frame(height: 64)
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
        .cardBackground()
    }
}
