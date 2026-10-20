import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairingSheet: View {
    @Environment(RemoteModel.self) private var remote
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("Pair a phone or browser").font(.title2.weight(.semibold))
            if let pairing = remote.pairing {
                if let url = pairing.url, let image = QRCode.image(for: url) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                        .accessibilityLabel("Pairing QR code")
                }
                Text(grouped(pairing.code))
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, pairing.expiresAt.timeIntervalSince(context.date))
                    Text(remaining > 0 ? "Expires in \(Int(remaining) / 60):\(String(format: "%02d", Int(remaining) % 60))" : "Expired")
                        .monospacedDigit()
                        .foregroundStyle(remaining > 30 ? Color.secondary : Color.orange)
                }
                Text("Scan with the Vitals app, or open the link on the phone. The code works once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let error = remote.adminError {
                Text(error).foregroundStyle(.orange)
            } else {
                ProgressView()
            }
            HStack {
                Button("New code") { Task { await remote.createPairing() } }
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 380)
        .task {
            var offered = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if remote.pairing != nil { offered = true }
                await remote.refreshDevices()
                if offered, remote.pairing == nil, remote.adminError == nil { isPresented = false }
            }
        }
    }

    private func grouped(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4).map { start -> String in
            let begin = code.index(code.startIndex, offsetBy: start)
            let end = code.index(begin, offsetBy: min(4, code.count - start))
            return String(code[begin..<end])
        }.joined(separator: " ")
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
