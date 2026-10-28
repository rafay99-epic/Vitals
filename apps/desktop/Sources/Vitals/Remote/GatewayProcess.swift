import Foundation

final class GatewayProcess: @unchecked Sendable {
    static let maxLineBytes = 1_048_576

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writeQueue = DispatchQueue(label: "vitals.gateway.write")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var buffer = Data()
    private let onMessage: @Sendable (ToApp) -> Void
    private let onInvalid: @Sendable (String) -> Void

    init(
        executable: URL,
        environment: [String: String],
        onMessage: @escaping @Sendable (ToApp) -> Void,
        onInvalid: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) {
        self.onMessage = onMessage
        self.onInvalid = onInvalid
        process.executableURL = executable
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { finished in onExit(finished.terminationStatus) }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    var pid: Int32 { process.processIdentifier }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.consume(chunk)
        }
        // The gateway's stderr is where Bun puts a crash or an unhandled error; keep it in the Remote log.
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            for line in String(decoding: chunk, as: UTF8.self).split(whereSeparator: \.isNewline) where !line.isEmpty {
                // Raw output (causes, payloads) stays local; a crash still reports as "gateway exited".
                Log.notice(.remote, "gateway: \(line.prefix(500))", report: false)
            }
        }
        try process.run()
    }

    func send(_ message: FromApp) {
        writeQueue.async { [weak self] in
            guard let self, self.process.isRunning else { return }
            do {
                var line = try self.encoder.encode(message)
                line.append(0x0A)
                try self.input.fileHandleForWriting.write(contentsOf: line)
            } catch {
                Log.error(.remote, "gateway write failed", error: error)
            }
        }
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            do {
                onMessage(try decoder.decode(ToApp.self, from: line))
            } catch {
                onInvalid(String(bytes: line.prefix(160), encoding: .utf8) ?? "\(line.count) unreadable bytes")
            }
        }
        if buffer.count > Self.maxLineBytes {
            onInvalid("oversized line dropped")
            buffer.removeAll(keepingCapacity: false)
        }
    }
}
