import Foundation

@MainActor
protocol CommandExecutor: AnyObject {
    func execute(_ command: RemoteCommand) async -> String?
}

@MainActor
final class CommandRouter {
    struct Request: Equatable {
        let id: String
        let deviceId: String
        let deviceName: String
        let command: RemoteCommand
    }

    private struct Pending {
        let request: Request
        var receipt: WireReceipt
        let timer: Timer
    }

    var onReceipt: (WireReceipt) -> Void = { _ in }
    var onGraceStarted: (Request, Date) -> Void = { _, _ in }
    var onGraceEnded: (String) -> Void = { _ in }
    var onWillPowerOff: () -> Void = {}

    private let executor: CommandExecutor
    private let clock: () -> Date
    private var pending: [String: Pending] = [:]
    private var finished: [String: WireReceipt] = [:]
    private var finishedOrder: [String] = []

    init(executor: CommandExecutor, clock: @escaping () -> Date = Date.init) {
        self.executor = executor
        self.clock = clock
    }

    var pendingIds: [String] { Array(pending.keys) }

    func run(_ request: Request) {
        if let receipt = finished[request.id] ?? pending[request.id]?.receipt {
            onReceipt(receipt)
            return
        }
        let now = clock()
        let grace = request.command.graceSeconds
        if grace > 0 {
            let deadline = now.addingTimeInterval(TimeInterval(grace))
            let receipt = makeReceipt(request, status: .pending, created: now, deadline: deadline)
            let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.fire(request.id) }
            }
            RunLoop.main.add(timer, forMode: .common)
            pending[request.id] = Pending(request: request, receipt: receipt, timer: timer)
            onReceipt(receipt)
            onGraceStarted(request, deadline)
            return
        }
        Task { await execute(request, created: now) }
    }

    func cancel(_ id: String) {
        guard let entry = pending.removeValue(forKey: id) else {
            if let receipt = finished[id] { onReceipt(receipt) }
            return
        }
        entry.timer.invalidate()
        onGraceEnded(id)
        finish(makeReceipt(entry.request, status: .cancelled, created: Date(timeIntervalSince1970: TimeInterval(entry.receipt.createdAt) / 1000), finished: clock()))
    }

    func fireNow(_ id: String) { fire(id) }

    private func fire(_ id: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timer.invalidate()
        onGraceEnded(id)
        let created = Date(timeIntervalSince1970: TimeInterval(entry.receipt.createdAt) / 1000)
        switch entry.request.command {
        case .restart, .shutDown, .logOut:
            onReceipt(makeReceipt(entry.request, status: .running, created: created))
            onWillPowerOff()
        default:
            break
        }
        Task { await execute(entry.request, created: created) }
    }

    private func execute(_ request: Request, created: Date) async {
        let error = await executor.execute(request.command)
        finish(makeReceipt(request, status: error == nil ? .done : .failed, created: created, finished: clock(), error: error))
    }

    private func finish(_ receipt: WireReceipt) {
        finished[receipt.id] = receipt
        finishedOrder.append(receipt.id)
        if finishedOrder.count > 200 {
            finished.removeValue(forKey: finishedOrder.removeFirst())
        }
        onReceipt(receipt)
    }

    private func makeReceipt(
        _ request: Request,
        status: WireReceipt.Status,
        created: Date,
        deadline: Date? = nil,
        finished: Date? = nil,
        error: String? = nil
    ) -> WireReceipt {
        WireReceipt(
            id: request.id,
            kind: request.command.tag,
            deviceId: request.deviceId,
            status: status,
            createdAt: Int64(created.timeIntervalSince1970 * 1000),
            deadlineAt: deadline.map { Int64($0.timeIntervalSince1970 * 1000) },
            finishedAt: finished.map { Int64($0.timeIntervalSince1970 * 1000) },
            error: error
        )
    }
}
