import SwiftUI

/// Phones that tried to reach this Mac in the last day: the ones the gateway turned away on Wi-Fi,
/// and the latest connection each paired phone opened. Read straight from the gateway's activity log,
/// so it shows what happened even while the Remote window was closed.
struct AttemptsCard: View {
    @Environment(RemoteModel.self) private var remote
    @State private var attempts = ActivityStore.Attempts()

    private static let store = ActivityStore(file: RemoteModel.dataDirectory.appendingPathComponent("activity.db"))

    var body: some View {
        SectionCard(title: "Phones that tried to connect", symbol: "antenna.radiowaves.left.and.right") {
            if attempts.refusals.isEmpty && attempts.visits.isEmpty {
                Text("Nothing in the last day.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(attempts.refusals) { refusal in
                        row(symbol: "exclamationmark", tint: .orange, title: title(refusal), detail: detail(refusal), at: refusal.last)
                        if refusal.id != attempts.refusals.last?.id || !attempts.visits.isEmpty { Divider() }
                    }
                    ForEach(attempts.visits) { visit in
                        row(
                            symbol: "checkmark",
                            tint: .green,
                            title: [name(visit.deviceId), visit.client].compactMap { $0 }.joined(separator: " · "),
                            detail: "Connected over \(visit.overWifi ? "Wi-Fi" : "Tailscale")",
                            at: visit.at
                        )
                        if visit.id != attempts.visits.last?.id { Divider() }
                    }
                }
            }
            if let last = attempts.lastReached {
                Text("Last connection \(last.formatted(.relative(presentation: .named))).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            while !Task.isCancelled {
                let since = Date().addingTimeInterval(-86_400)
                let store = Self.store
                attempts = await Task.detached(priority: .utility) { store.attempts(since: since) }.value
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func row(symbol: String, tint: Color, title: String, detail: String, at: Date) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint, size: 26, font: .system(size: 12, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(at.formatted(date: .omitted, time: .shortened))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func name(_ deviceId: String) -> String? {
        remote.devices.first { $0.id == deviceId }?.name ?? "A removed device"
    }

    private func title(_ refusal: ActivityStore.Refusal) -> String {
        [refusal.address, refusal.client].compactMap { $0 }.joined(separator: " · ")
    }

    /// The gateway's reason, in words that say what to do.
    private func detail(_ refusal: ActivityStore.Refusal) -> String {
        let since = "since \(refusal.first.formatted(date: .omitted, time: .shortened))"
        switch refusal.why {
        case "handshake for another Mac key": return "Holds a key for another Mac. Pair it again · \(since)"
        case "unknown phone key": return "This Mac doesn't know it. Pair it again · \(since)"
        case "device has no session": return "Its pairing ended. Pair it again · \(since)"
        case "other protocol": return "Runs another Vitals Remote version. Update both · \(since)"
        case "too many pairing requests": return "Too many pairing requests · \(since)"
        case "frame did not decrypt": return "A message didn't decrypt; it reconnects · \(since)"
        default: return "Turned away: \(refusal.why) · \(since)"
        }
    }
}
