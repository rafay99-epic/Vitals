import Observation

/// Calls `action` on the main actor each time `value()` changes (never for the
/// initial value): `withObservationTracking` re-armed after every change. The
/// `@Observable` replacement for `$property.dropFirst().removeDuplicates().sink`.
/// Lives as long as the observed object keeps mutating, so use it for
/// app-lifetime wiring and capture `self` weakly in both closures.
@MainActor
func observeChanges<T: Equatable>(of value: @escaping @MainActor () -> T,
                                  _ action: @escaping @MainActor (T) -> Void) {
    ChangeObserver(value: value, action: action).track()
}

@MainActor
private final class ChangeObserver<T: Equatable> {
    private let value: @MainActor () -> T
    private let action: @MainActor (T) -> Void
    private var last: T

    init(value: @escaping @MainActor () -> T, action: @escaping @MainActor (T) -> Void) {
        self.value = value
        self.action = action
        last = value()
    }

    func track() {
        // onChange fires before the new value lands, so read it on the next hop.
        withObservationTracking { _ = value() } onChange: {
            Task { @MainActor in self.fire() }
        }
    }

    private func fire() {
        let new = value()
        track()
        guard new != last else { return }
        last = new
        action(new)
    }
}
