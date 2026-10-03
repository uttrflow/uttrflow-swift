import UttrflowCore

/// Verdicts already reached, so that most keystrokes cost nothing at all.
struct VerdictCache: Sendable {
    /// How many verdicts are kept, which is a few keystrokes' worth of candidates and no more.
    static let capacity = 64

    /// How long a verdict is believed, since an alias defined a moment ago has to be able to win.
    static let lifetimeInSeconds = 5.0

    /// What a verdict is remembered against, which is the candidate and everything around it.
    struct Key: Hashable, Sendable {
        /// The candidate the gates judged.
        let candidate: String
        /// The field and what has been typed into it, since the same word is not the same twice.
        let context: String
    }

    /// The verdicts, least recently used dropped first past capacity.
    private var held = BoundedCache<Key, Verdict>(
        capacity: capacity, lifetime: .seconds(lifetimeInSeconds))

    /// A cache holding nothing.
    init() {}

    /// How many verdicts are remembered, for the tests and the diagnostics page.
    var count: Int { held.count }

    /// The verdict on this key, absent when there is none or the one there has expired.
    mutating func verdict(for key: Key, now: ContinuousClock.Instant = .now) -> Verdict? {
        held.value(for: key, now: now)
    }

    /// Remembers one verdict, dropping what has expired and then the least recently used to stay within capacity.
    mutating func remember(
        _ verdict: Verdict, for key: Key, now: ContinuousClock.Instant = .now
    ) {
        held.store(verdict, for: key, now: now)
    }

    /// Forgets everything, which is what leaving a field and the reset in Settings both ask for.
    mutating func forgetEverything() {
        held.forgetEverything()
    }
}
