import SwiftUI

struct PhonePicker: View {
    @Environment(ShareModel.self) private var share
    let batch: ShareModel.Batch
    let onSend: ([String]) -> Void
    let onCancel: () -> Void
    @State private var selection: Set<String>

    init(batch: ShareModel.Batch, selection: Set<String>, onSend: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
        self.batch = batch
        self.onSend = onSend
        self.onCancel = onCancel
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let phones = share.phones
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(phones.count == 2 ? "Send to \(phones[0].name) or \(phones[1].name)?" : "Send to which phone?")
                    .font(.system(size: 13, weight: .semibold))
                Text(batch.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            PhoneChoices(phones: phones, selection: $selection, lastUsed: share.lastPhone)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Send to \(chosen.count == 2 ? "both" : "\(chosen.count)")" : "Send") { onSend(chosen) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var chosen: [String] { share.phones.map(\.id).filter(selection.contains) }
}
