import SwiftUI

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26
    var font: Font = .system(size: 12, weight: .medium)
    var cornerRadius: CGFloat = 7

    var body: some View {
        Image(systemName: symbol)
            .font(font)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.14)))
    }
}

struct SelectionMark: View {
    let selected: Bool
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size))
            .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
    }
}

extension View {
    func capsuleTag(_ tint: Color, fill: Double = 0.18, horizontal: CGFloat = 8, vertical: CGFloat = 3) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(Capsule().fill(tint.opacity(fill)))
            .foregroundStyle(tint)
    }
}

struct HeroReadout<Trailing: View>: View {
    let value: String
    let caption: String
    var large = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: large ? 40 : 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericTransition()
            Text(caption)
                .font(large ? .title3 : .callout)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
    }
}

extension HeroReadout where Trailing == EmptyView {
    init(value: String, caption: String, large: Bool = false) {
        self.init(value: value, caption: caption, large: large) { EmptyView() }
    }
}

struct PageHero<Controls: View>: View {
    let value: String
    let subtitle: String
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            controls()
        }
    }
}

struct ScanButtons: View {
    let isScanning: Bool
    let hasRun: Bool
    let disabled: Bool
    let help: String
    let scan: () -> Void
    let stop: () -> Void

    var body: some View {
        if isScanning {
            ProgressView()
                .controlSize(.small)
            Button(role: .cancel, action: stop) {
                Label("Stop", systemImage: "stop.fill")
            }
            .controlSize(.large)
            .help("Stop scanning")
        } else {
            Button(action: scan) {
                Label(hasRun ? "Rescan" : "Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(disabled)
            .help(help)
        }
    }
}
