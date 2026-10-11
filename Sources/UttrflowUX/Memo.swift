// Keeps derived values while their source is unchanged.
private import Synchronization

/// Remembers a derived value for each key's current source.
final class Memo<Key: Hashable & Sendable, Source: Equatable & Sendable, Value: Sendable>: Sendable {
    private struct Entry {
        let source: Source
        let value: Value
    }

    private let entries = Mutex<[Key: Entry]>([:])
    private let limit: Int?

    init(limit: Int? = nil) {
        self.limit = limit
    }

    var count: Int { entries.withLock { $0.count } }

    func remembers(_ key: Key) -> Bool { entries.withLock { $0[key] != nil } }

    /// Builds a miss outside the lock; concurrent misses keep their own result and the last store wins.
    func value(for key: Key, source: Source, building build: () -> Value) -> Value {
        if let known = entries.withLock({ $0[key] }), known.source == source {
            return known.value
        }
        let value = build()
        entries.withLock { entries in
            if entries[key] == nil, let limit, entries.count >= limit { entries.removeAll() }
            entries[key] = Entry(source: source, value: value)
        }
        return value
    }

    /// Drops values for keys absent from the live set.
    func prune(to liveKeys: Set<Key>) {
        entries.withLock { entries in
            entries = entries.filter { liveKeys.contains($0.key) }
        }
    }
}
