import Foundation

@MainActor
@Observable
final class ActivityModel {
    nonisolated private static let kept = 1000

    private(set) var events: [ActivityStore.Event] = []
    private(set) var summary = ActivityStore.Summary()
    private(set) var frames: [ActivityStore.Frame] = []
    @ObservationIgnored private var frameLoad = 0
    var filter = ActivityStore.Filter() { didSet { if filter != oldValue { reload() } } }
    var following: String? { didSet { loadFrames() } }

    @ObservationIgnored private let store: ActivityStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var version: Int64 = -2

    init(store: ActivityStore = ActivityStore(file: RemoteModel.dataDirectory.appendingPathComponent("activity.db"))) {
        self.store = store
    }

    func setVisible(_ visible: Bool) {
        timer?.invalidate()
        timer = nil
        guard visible else { return }
        reload()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let store = store
        let filter = filter
        let after = events.first?.id ?? 0
        let known = version
        Task.detached(priority: .utility) {
            let current = store.dataVersion()
            guard current != known else { return }
            let fresh = store.events(filter: filter, afterSeq: after, limit: Self.kept)
            let summary = store.summary(since: Calendar.current.startOfDay(for: Date()))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.version = current
                if !fresh.isEmpty { self.events = Array((fresh + self.events).prefix(Self.kept)) }
                self.summary = summary
                if self.following != nil { self.loadFrames() }
            }
        }
    }

    func reload() {
        let store = store
        let filter = filter
        Task.detached(priority: .utility) {
            let rows = store.events(filter: filter, limit: 500)
            let summary = store.summary(since: Calendar.current.startOfDay(for: Date()))
            let current = store.dataVersion()
            await MainActor.run { [weak self] in
                self?.events = rows
                self?.summary = summary
                self?.version = current
            }
        }
    }

    private func loadFrames() {
        guard let connection = following else {
            frames = []
            return
        }
        let store = store
        frameLoad += 1
        let load = frameLoad
        Task.detached(priority: .utility) {
            let rows = store.frames(connectionId: connection)
            await MainActor.run { [weak self] in
                guard let self, self.frameLoad == load else { return }
                self.frames = rows
            }
        }
    }
}
