/// A map that keeps at most `capacity` entries, dropping the least recently used, each optionally believed for a lifetime.
public struct BoundedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    /// One entry, its expiry, and its neighbours in recency order.
    private struct Node: Sendable {
        var value: Value
        var expires: ContinuousClock.Instant?
        var newer: Key?
        var older: Key?
    }

    /// The most entries held at once.
    public let capacity: Int
    /// How long an entry is believed after it is stored, absent when it is believed until evicted.
    public let lifetime: Duration?

    /// Each entry against its key.
    private var nodes: [Key: Node] = [:]
    /// The most recently used key.
    private var newest: Key?
    /// The least recently used key, which is what capacity drops first.
    private var oldest: Key?

    /// An empty cache; a capacity below one holds nothing.
    public init(capacity: Int, lifetime: Duration? = nil) {
        self.capacity = max(0, capacity)
        self.lifetime = lifetime
    }

    /// How many entries are held, expired ones included until they are next swept.
    public var count: Int { nodes.count }

    /// The value for this key, marked most recently used, absent when there is none or it has expired.
    public mutating func value(for key: Key, now: ContinuousClock.Instant = .now) -> Value? {
        guard let node = nodes[key] else { return nil }
        if let expires = node.expires, expires <= now { return nil }
        unlink(key)
        linkAsNewest(key)
        return node.value
    }

    /// Stores one value as most recently used, sweeping what has expired and then the least recently used past capacity.
    public mutating func store(_ value: Value, for key: Key, now: ContinuousClock.Instant = .now) {
        guard capacity > 0 else { return }
        discardExpired(now: now)
        let expires = lifetime.map { now + $0 }
        if nodes[key] != nil { unlink(key) }
        nodes[key] = Node(value: value, expires: expires, newer: nil, older: nil)
        linkAsNewest(key)
        while nodes.count > capacity, let victim = oldest { remove(victim) }
    }

    /// Removes one key, if held.
    public mutating func remove(_ key: Key) {
        guard nodes[key] != nil else { return }
        unlink(key)
        nodes.removeValue(forKey: key)
    }

    /// Forgets every entry, which is what the privacy and reset paths ask of every cache.
    public mutating func forgetEverything() {
        nodes.removeAll()
        newest = nil
        oldest = nil
    }

    /// Drops the expired entries, so capacity is spent on the ones that still count.
    private mutating func discardExpired(now: ContinuousClock.Instant) {
        guard lifetime != nil else { return }
        let expired = nodes.compactMap { key, node in
            node.expires.map { $0 <= now } == true ? key : nil
        }
        for key in expired { remove(key) }
    }

    /// Takes a held key out of the recency chain without removing its entry.
    private mutating func unlink(_ key: Key) {
        guard let node = nodes[key] else { return }
        if let newer = node.newer { nodes[newer]?.older = node.older } else { newest = node.older }
        if let older = node.older { nodes[older]?.newer = node.newer } else { oldest = node.newer }
        nodes[key]?.newer = nil
        nodes[key]?.older = nil
    }

    /// Puts a held, unlinked key at the most recently used end of the chain.
    private mutating func linkAsNewest(_ key: Key) {
        nodes[key]?.older = newest
        nodes[key]?.newer = nil
        if let previous = newest { nodes[previous]?.newer = key }
        newest = key
        if oldest == nil { oldest = key }
    }
}
