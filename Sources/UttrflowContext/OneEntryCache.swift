import Synchronization

/// Keeps one value and drops it whenever a lookup names another key.
final class OneEntryCache<Key: Equatable & Sendable, Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        let key: Key
        let value: Value
    }

    /// The retained value, and how many clears have happened, so a read begun before a clear cannot refill it.
    private struct State: Sendable {
        var entry: Entry?
        var generation: UInt64 = 0
    }

    private let state = Mutex(State())

    /// The count of clears so far, taken when a read begins and handed back to `insert`.
    var generation: UInt64 { state.withLock { $0.generation } }

    /// Returns the value for `key`, evicting an answer for a different identity.
    func value(for key: Key) -> Value? {
        state.withLock { state in
            guard let current = state.entry else { return nil }
            guard current.key == key else {
                state.entry = nil
                return nil
            }
            return current.value
        }
    }

    /// Replaces the one retained value, unless the cache was cleared after `generation` was taken.
    @discardableResult
    func insert(_ value: Value, for key: Key, readSince generation: UInt64? = nil) -> Bool {
        state.withLock { state in
            if let generation, generation != state.generation { return false }
            state.entry = Entry(key: key, value: value)
            return true
        }
    }

    /// Releases the retained value when its answers may have changed.
    func clear() {
        state.withLock { state in
            state.entry = nil
            state.generation &+= 1
        }
    }
}
