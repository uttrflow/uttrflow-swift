import struct Foundation.Date

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

    /// One verdict and the moment it stops being believed.
    private struct Held {
        let verdict: Verdict
        let expires: Date
    }

    /// Each verdict against the key it answers.
    private var held: [Key: Held] = [:]
    /// The keys in the order they were first remembered, which is what capacity drops from.
    private var order: [Key] = []

    /// A cache holding nothing.
    init() {}

    /// How many verdicts are remembered, for the tests and the diagnostics page.
    var count: Int { held.count }

    /// The verdict on this key, absent when there is none or the one there has expired.
    func verdict(for key: Key, now: Date) -> Verdict? {
        guard let entry = held[key], entry.expires > now else { return nil }
        return entry.verdict
    }

    /// Remembers one verdict, dropping what has expired and then the oldest to stay within capacity.
    mutating func remember(_ verdict: Verdict, for key: Key, now: Date) {
        discardExpired(now: now)
        if held[key] == nil { order.append(key) }
        held[key] = Held(verdict: verdict, expires: now.addingTimeInterval(Self.lifetimeInSeconds))
        while order.count > Self.capacity {
            held.removeValue(forKey: order.removeFirst())
        }
    }

    /// Forgets everything, which is what leaving a field and the reset in Settings both ask for.
    mutating func forgetEverything() {
        held.removeAll()
        order.removeAll()
    }

    /// Drops the expired verdicts, so capacity is spent on the ones that still count.
    private mutating func discardExpired(now: Date) {
        guard held.contains(where: { $0.value.expires <= now }) else { return }
        order.removeAll { key in held[key].map { $0.expires <= now } ?? true }
        held = held.filter { $0.value.expires > now }
    }
}
