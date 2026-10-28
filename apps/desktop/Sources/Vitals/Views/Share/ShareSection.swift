import SwiftUI

struct ShareSection: View {
    @Environment(ShareModel.self) private var share

    var body: some View {
        let now = Date()
        let asks = share.asks
        let active = share.active
        let waiting = share.waiting
        let done = share.latestDone(now: now)
        let sent = share.freshClipSent(now: now)
        let copy = share.freshPhoneCopy(now: now)
        if !asks.isEmpty || !active.isEmpty || !waiting.isEmpty || done != nil || sent != nil || copy != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Share")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(asks) { AskLine(drop: $0) }
                ForEach(active) { TransferLine(drop: $0) }
                ForEach(waiting) { WaitingLine(drop: $0) }
                if let done { DoneLine(drop: done) }
                if let sent {
                    line(symbol: "checkmark.circle.fill", tint: .green) {
                        Text("Sent your clipboard to \(sent.to)").lineLimit(1)
                    }
                }
                if let copy { PhoneCopyLine(copy: copy) }
            }
            .font(.system(size: 12))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .insetCard(fill: 0.4, border: 0.4, cornerRadius: 9)
        }
    }
}

private func line(symbol: String, tint: Color, @ViewBuilder content: () -> some View) -> some View {
    HStack(spacing: 8) {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(tint)
            .frame(width: 16)
        content()
    }
}

private struct AskLine: View {
    @Environment(ShareModel.self) private var share
    let drop: Drop

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            line(symbol: "questionmark.circle.fill", tint: .orange) {
                (Text(drop.phone.name).fontWeight(.medium)
                    + Text(" wants to send \(drop.files.count == 1 ? drop.files[0].name : ShareFormat.files(drop.files.count))").foregroundStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Text(ShareFormat.size(drop.bytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, 24)
                Spacer()
                Button("Decline") { share.decide(drop.id, accept: false) }
                Button("Accept") { share.decide(drop.id, accept: true) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }
}

private struct TransferLine: View {
    let drop: Drop

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            line(symbol: drop.isOutgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill", tint: drop.isOutgoing ? .blue : .green) {
                (Text(ShareModel.label(drop)).fontWeight(.medium)
                    + Text(" \(drop.isOutgoing ? "to" : "from") \(drop.phone.name)").foregroundStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                DropControls(drop: drop)
            }
            ProgressView(value: drop.fraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
            HStack {
                Text(([ShareFormat.progress(drop.done, of: drop.bytes), drop.route?.label] as [String?]).compactMap { $0 }.joined(separator: " · "))
                Spacer()
                Text(drop.state == .paused ? "Paused" : "\(drop.percent)%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

private struct WaitingLine: View {
    @Environment(ShareModel.self) private var share
    let drop: Drop

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line(symbol: "clock.fill", tint: .orange) {
                Text("Waiting for \(drop.phone.name). Open Vitals on the phone.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Cancel") { share.cancel(drop.id) }
                    .controlSize(.small)
            }
            Text("\(ShareModel.label(drop)) · \(ShareFormat.size(drop.bytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, 24)
        }
    }
}

private struct DoneLine: View {
    @Environment(ShareModel.self) private var share
    let drop: Drop

    var body: some View {
        line(symbol: "checkmark.circle.fill", tint: .green) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Text("\(drop.isOutgoing ? "to" : "from") \(drop.phone.name) · \(ShareFormat.size(drop.bytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if !drop.isOutgoing {
                Button("Show in Finder") { share.reveal(drop.id) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private var title: String {
        guard !drop.isOutgoing else { return "Sent \(ShareModel.label(drop))" }
        return drop.files.count > 1 ? "Got \(ShareFormat.files(drop.files.count))" : "Got \(ShareModel.label(drop))"
    }
}

private struct PhoneCopyLine: View {
    @Environment(ShareModel.self) private var share
    let copy: ShareModel.PhoneCopy

    var body: some View {
        let copied = NSPasteboard.general.changeCount == copy.changeCount
        line(symbol: "doc.on.clipboard", tint: .secondary) {
            (Text("\(copy.device) copied: ").foregroundStyle(.secondary) + Text(copy.preview))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button(copied ? "Copied" : "Copy") { share.copyPhoneCopy() }
                .controlSize(.small)
                .disabled(copied)
        }
    }
}
