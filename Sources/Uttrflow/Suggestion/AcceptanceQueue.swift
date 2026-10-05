import Foundation

/// Records accepted suggestions one after another and off the key path, so a held key never waits on the corpus.
@MainActor
final class AcceptanceQueue {
    /// The newest recording, which every later one waits behind.
    private var last: Task<Void, Never>?
    /// Whether a forget is draining the old corpus and must refuse newly accepted writes.
    private var forgetCount = 0

    /// Queues `work` behind every earlier recording and returns at once.
    @discardableResult
    func enqueue(_ work: @escaping @Sendable () async -> Void) -> Bool {
        guard forgetCount == 0 else { return false }
        let previous = last
        last = Task {
            await previous?.value
            await work()
        }
        return true
    }

    /// Waits until every recording queued so far has finished, so capture hears of the acceptance first.
    func drained() async {
        await last?.value
    }

    /// Closes admission before waiting for every previously queued write to finish.
    func beginForgetting() async {
        forgetCount += 1
        await last?.value
    }

    /// Reopens admission after the corpus and its in-memory copies have been cleared.
    func finishForgetting() {
        forgetCount = max(0, forgetCount - 1)
    }
}
