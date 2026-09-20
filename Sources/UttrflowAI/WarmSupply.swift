// One prepared thing kept ready for whoever asks next, and made again as soon as one is taken.

internal import struct Foundation.Date

/// Keeps something expensive ready before it is needed, so only the first asker pays for making it.
actor WarmSupply<Prepared: Sendable> {
    /// How long a prepared thing counts as warm; past this the machine has let it go cold.
    static var staleAfterSeconds: Double { 60 }

    /// Makes one, prepared as far as it can be before the request that will use it.
    private let make: @Sendable (String) -> Prepared

    /// What the supply reads the time from, so a test can move it.
    private let now: @Sendable () -> Date

    /// When `ready` was made, so one that has gone cold is made again rather than handed out.
    private var madeAt = Date.distantPast

    /// The one made ahead of time, if any.
    private var ready: Prepared?

    /// What `ready` was made for; a request carrying anything else cannot use it.
    private var madeFor: String?

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        make: @escaping @Sendable (String) -> Prepared
    ) {
        self.make = make
        self.now = now
    }

    /// Keeps one for the next request carrying `key`, dropping any earlier one.
    func keep(_ prepared: Prepared, for key: String) {
        ready = prepared
        madeFor = key
        madeAt = now()
    }

    /// The one kept for `key`, handed out once; a request for anything else empties the slot instead.
    func take(for key: String) -> Prepared? {
        defer { ready = nil }
        guard madeFor == key else {
            madeFor = nil
            return nil
        }
        // One that has gone cold is no better than none: the caller makes a fresh one either way.
        return isStale ? nil : ready
    }

    /// Makes the next one, so a second and third request pay no more than the first did.
    func replenish(for key: String) {
        // A session kept since the last dictation has gone cold, so age replaces it as a wrong key would.
        guard ready == nil || madeFor != key || isStale else { return }
        ready = make(key)
        madeFor = key
        madeAt = now()
    }

    /// Whether what is kept was made too long ago to still be warm.
    private var isStale: Bool {
        now().timeIntervalSince(madeAt) >= Self.staleAfterSeconds
    }

    /// Whether one is waiting for `key` right now, which is what the supply exists to keep true.
    func isReady(for key: String) -> Bool { ready != nil && madeFor == key && !isStale }
}
