public import struct Foundation.Date

/// Verdicts already reached, so that most keystrokes cost nothing at all.
public struct VerdictCache: Sendable {
    /// How many verdicts are kept, which is a few keystrokes' worth of candidates and no more.
    public static let capacity = 64

    /// How long a verdict is believed, since an alias defined a moment ago has to be able to win.
    public static let lifetimeInSeconds = 5.0

    /// What a verdict is remembered against, which is the candidate and everything around it.
    public struct Key: Hashable, Sendable {
        /// The candidate the gates judged.
        public let candidate: String
        /// The field and what has been typed into it, since the same word is not the same twice.
        public let context: String

        public init(candidate: String, context: String) {
            self.candidate = candidate
            self.context = context
        }
    }

    /// One verdict and the moment it stops being believed.
    private struct Held {
        let verdict: Verdict
        let expires: Date
    }

    private var held: [Key: Held] = [:]
    private var order: [Key] = []

    public init() {}

    /// How many verdicts are remembered, for the tests and the diagnostics page.
    public var count: Int { held.count }

    /// What was decided about this key, absent when nothing was or what was is no longer believed.
    public func verdict(for key: Key, now: Date) -> Verdict? {
        guard let entry = held[key], entry.expires > now else { return nil }
        return entry.verdict
    }

    /// Remembers one verdict, dropping what has expired and then the oldest to stay within capacity.
    public mutating func remember(_ verdict: Verdict, for key: Key, now: Date) {
        discardExpired(now: now)
        if held[key] == nil { order.append(key) }
        held[key] = Held(verdict: verdict, expires: now.addingTimeInterval(Self.lifetimeInSeconds))
        while order.count > Self.capacity {
            held.removeValue(forKey: order.removeFirst())
        }
    }

    /// Forgets everything, which is what leaving a field and the reset in Settings both ask for.
    public mutating func forgetEverything() {
        held.removeAll()
        order.removeAll()
    }

    /// Drops what is no longer believed, so capacity is spent on verdicts that still count.
    private mutating func discardExpired(now: Date) {
        guard held.contains(where: { $0.value.expires <= now }) else { return }
        order.removeAll { key in held[key].map { $0.expires <= now } ?? true }
        held = held.filter { $0.value.expires > now }
    }
}
