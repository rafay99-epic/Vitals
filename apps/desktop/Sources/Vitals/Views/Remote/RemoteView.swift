import SwiftUI

struct RemoteView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case devices = "Devices"
        case activity = "Activity"
        case pressure = "Pressure Guard"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .devices

    var body: some View {
        VStack(spacing: 0) {
            Picker("Remote", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.top, 16)
            switch tab {
            case .devices: RemoteDevicesTab()
            case .activity: ActivityView()
            case .pressure: GuardView()
            }
        }
    }
}

private struct RemoteDevicesTab: View {
    @Environment(RemoteModel.self) private var remote
    @State private var showingPairing = false

    var body: some View {
        MetricScroll {
            StatusCard()
            if !remote.pendingCommands.isEmpty { PendingCommandsCard() }
            KeepAwakeCard()
            SectionCard(title: "Devices", symbol: "iphone.gen3") {
                if remote.devices.isEmpty {
                    Text(remote.isEnabled ? "No paired devices yet." : "Turn on remote access to pair a phone.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(remote.devices) { device in
                            DeviceRow(device: device)
                            if device.id != remote.devices.last?.id { Divider() }
                        }
                    }
                }
                Button("Pair new device") {
                    showingPairing = true
                    Task { await remote.createPairing() }
                }
                .disabled(remote.state != .running)
            }
        }
        .sheet(isPresented: $showingPairing, onDismiss: { remote.clearPairing() }) {
            PairingSheet(isPresented: $showingPairing)
        }
        .task(id: remote.state) { await remote.refreshDevices() }
    }
}

private struct StatusCard: View {
    @Environment(RemoteModel.self) private var remote

    var body: some View {
        SectionCard(title: "Remote access", symbol: "dot.radiowaves.left.and.right") {
            Toggle(isOn: Binding(get: { remote.isEnabled }, set: { remote.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.body.weight(.medium))
                    if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            .toggleStyle(.switch)
            if let status = remote.status, remote.isEnabled {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    check("Tailscale serve", ok: status.serve == .serving, value: status.serve.rawValue)
                    check("Owner", ok: status.ownerLogin != nil, value: status.ownerLogin ?? "unknown")
                    check("Connected", ok: true, value: "\(status.clients) socket\(status.clients == 1 ? "" : "s")")
                }
                .font(.callout)
            }
        }
    }

    private var headline: String {
        switch remote.state {
        case .off: return "Off"
        case .starting: return "Starting"
        case .running: return remote.status?.serve == .serving ? "Serving on your tailnet" : "Running"
        case let .restarting(attempt): return "Restarting (attempt \(attempt))"
        case .failed: return "Unavailable"
        }
    }

    private var detail: String? {
        if case let .failed(message) = remote.state { return message }
        guard remote.isEnabled else { return "Phones and browsers on your tailnet can monitor and control this Mac." }
        return remote.status?.url ?? remote.status?.detail
    }

    private func check(_ title: String, ok: Bool, value: String) -> some View {
        GridRow {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

private struct PendingCommandsCard: View {
    @Environment(RemoteModel.self) private var remote

    var body: some View {
        SectionCard(title: "Pending", symbol: "timer") {
            ForEach(remote.pendingCommands.keys.sorted(), id: \.self) { id in
                if let entry = remote.pendingCommands[id] {
                    HStack {
                        Text("\(entry.kind) from \(entry.deviceName)")
                        Spacer()
                        Text(entry.deadline, style: .timer).monospacedDigit().foregroundStyle(.secondary)
                        Button("Cancel", role: .destructive) { remote.cancelPending(id) }
                    }
                }
            }
        }
    }
}

private struct KeepAwakeCard: View {
    @Environment(RemoteModel.self) private var remote

    var body: some View {
        SectionCard(title: "Keep awake", symbol: "cup.and.saucer") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(remote.keepAwake.active ? "This Mac stays awake" : "Normal sleep")
                    if let until = remote.keepAwake.until {
                        Text("Until \(until.formatted(date: .omitted, time: .shortened))").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(remote.keepAwake.active ? "Allow sleep" : "Keep awake") { remote.toggleKeepAwake() }
            }
        }
    }
}

private struct DeviceRow: View {
    @Environment(RemoteModel.self) private var remote
    let device: RemoteDevice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: device.platform == "web" ? "globe" : "iphone.gen3")
                .font(.title3)
                .foregroundStyle(device.connected ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name).font(.body.weight(.medium))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    scopeToggle("operate", title: "Control")
                    scopeToggle("destructive", title: "Shut down, kill, force quit")
                    scopeToggle("clipboard", title: "Read clipboard")
                }
                .font(.callout)
            }
            Spacer()
            Button("Revoke", role: .destructive) { Task { await remote.revoke(device) } }
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        let seen = device.lastSeenAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000).formatted(.relative(presentation: .named)) } ?? "never"
        return "\(device.model) · app \(device.appVersion) · \(device.connected ? "connected" : "last seen \(seen)")"
    }

    private func scopeToggle(_ scope: String, title: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { device.scopes.contains(scope) },
            set: { enabled in Task { await remote.setScope(scope, enabled: enabled, for: device) } }
        ))
        .toggleStyle(.checkbox)
    }
}
