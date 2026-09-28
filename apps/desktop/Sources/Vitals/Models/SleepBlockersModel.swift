import Foundation

/// Apps holding a sleep assertion, re-read every 5 s while `watch()` runs. The
/// Battery section runs it for as long as its card is on screen.
@MainActor
@Observable
final class SleepBlockersModel {
    /// Nil until the first read lands.
    private(set) var blockers: [SleepBlocker]?

    func watch() async {
        while !Task.isCancelled {
            blockers = await Task.detached(priority: .utility) { PowerAssertions.blockers() }.value
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
