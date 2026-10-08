// Fans the pipeline's state out to every watcher.
import Foundation
private import Synchronization

/// Fans one sequence of values out to every watcher, since a single stream has one consumer.
final class StateObservers<Value: Sendable>: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Value>.Continuation]>([:])

    /// A stream that begins with the current state, so a late watcher is not left blank.
    func makeStream(startingWith current: Value) -> AsyncStream<Value> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Value>.makeStream()
        continuation.yield(current)
        // Captures self rather than the Mutex, which is non-copyable and cannot enter a capture list.
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { $0[id] = nil }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    func send(_ state: Value) {
        for continuation in continuations.withLock({ $0.values }) {
            continuation.yield(state)
        }
    }

}
