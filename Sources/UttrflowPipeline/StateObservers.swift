import Foundation
import UttrflowCore
private import Synchronization

/// Fans one sequence of states out to every interested watcher.
///
/// The menu bar icon, the floating button and the debug panel all follow the same
/// dictation, so a single stream would have to be shared and could be consumed by
/// whichever asked first.
final class StateObservers: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<DictationState>.Continuation]>([:])

    /// A stream that begins with the current state, so a watcher that arrives late is
    /// not left blank until something next happens.
    func makeStream(startingWith current: DictationState) -> AsyncStream<DictationState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<DictationState>.makeStream()
        continuation.yield(current)
        // Captures self rather than the Mutex: a Mutex is non-copyable, so it cannot
        // be pulled into a closure's capture list.
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { $0[id] = nil }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    func send(_ state: DictationState) {
        for continuation in continuations.withLock({ $0.values }) {
            continuation.yield(state)
        }
    }

    /// Number of live watchers. Lets a test prove that a finished stream is let go of
    /// rather than leaked.
    var observerCount: Int { continuations.withLock(\.count) }
}
