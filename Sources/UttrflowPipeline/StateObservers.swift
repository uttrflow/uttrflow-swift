// Fans the pipeline's state out to every watcher.
import Foundation
import UttrflowCore
private import Synchronization

/// Fans one sequence of states out to every watcher, since a single stream has one consumer.
final class StateObservers: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<DictationState>.Continuation]>([:])

    /// A stream that begins with the current state, so a late watcher is not left blank.
    func makeStream(startingWith current: DictationState) -> AsyncStream<DictationState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<DictationState>.makeStream()
        continuation.yield(current)
        // Captures self rather than the Mutex, which is non-copyable and cannot enter a capture list.
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

    /// Number of live watchers, so a test can prove a finished stream is let go of.
    var observerCount: Int { continuations.withLock(\.count) }
}
