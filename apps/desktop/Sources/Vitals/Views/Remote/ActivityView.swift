import SwiftUI

struct ActivityView: View {
    @State private var model = ActivityModel()
    @State private var selection: ActivityStore.Event.ID?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                stat("Events today", model.summary.events)
                stat("Errors", model.summary.errors)
                stat("Connections", model.summary.connections)
                stat("Frames", model.summary.frames)
                Spacer()
            }
            HStack {
                Picker("Source", selection: $model.filter.source) {
                    Text("All sources").tag(String?.none)
                    ForEach(["gateway", "desktop", "client"], id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(width: 170)
                Picker("Level", selection: $model.filter.level) {
                    Text("All levels").tag(String?.none)
                    ForEach(["debug", "info", "warn", "error"], id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(width: 150)
                TextField("Filter kind, rpc, data", text: $model.filter.text)
                    .textFieldStyle(.roundedBorder)
            }
            HSplitView {
                Table(model.events, selection: $selection) {
                    TableColumn("Time") { Text($0.at.formatted(date: .omitted, time: .standard)).monospacedDigit() }
                        .width(min: 80, ideal: 90)
                    TableColumn("Level") { Text($0.level).foregroundStyle(color($0.level)) }.width(50)
                    TableColumn("Source", value: \.source).width(60)
                    TableColumn("Kind", value: \.kind).width(min: 140, ideal: 180)
                    TableColumn("RPC") { Text($0.rpc ?? "") }.width(min: 80, ideal: 110)
                    TableColumn("ms") { Text($0.durationMs.map { String(format: "%.1f", $0) } ?? "").monospacedDigit() }.width(50)
                }
                .frame(minWidth: 520)
                ActivityDetail(event: model.events.first { $0.id == selection }, model: model)
                    .frame(minWidth: 240, idealWidth: 300)
            }
        }
        .padding(20)
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private func color(_ level: String) -> Color {
        switch level {
        case "error": return .red
        case "warn": return .orange
        case "debug": return .secondary
        default: return .primary
        }
    }
}

private struct ActivityDetail: View {
    let event: ActivityStore.Event?
    let model: ActivityModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let event {
                    Text(event.kind).font(.headline)
                    detailRow("Device", event.deviceId)
                    detailRow("Connection", event.connectionId)
                    detailRow("Command", event.commandId)
                    Text(event.data).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    if let connection = event.connectionId {
                        Button(model.following == connection ? "Stop following" : "Follow connection") {
                            model.following = model.following == connection ? nil : connection
                        }
                    }
                    if model.following != nil {
                        Divider()
                        ForEach(model.frames) { frame in
                            HStack {
                                Image(systemName: frame.direction == "in" ? "arrow.down" : "arrow.up")
                                Text(frame.tag)
                                Text(frame.method ?? "").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(frame.bytes) B").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    Text("Select an event").foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .top) {
                Text(title).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                Text(value).textSelection(.enabled)
            }
            .font(.callout)
        }
    }
}
