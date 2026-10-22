// Holds one delete that waits for a spoken confirmation word, in memory only.
private import Synchronization
import UttrflowCore

/// The word that confirms a delete over more than one line, and how long it may take to be heard.
enum ConfirmationPolicy {
    /// The word heard whole under the command key.
    static let word = "confirm"
    /// How long after the ask the word still counts.
    static let window: Duration = .seconds(3)
}

/// A delete asked for and not yet confirmed; it names the span but never keeps its text, and expires on its own.
final class PendingConfirmation: Sendable {
    private struct Entry: Sendable {
        let record: InsertionRecord
        let askedAt: UInt64
    }

    private let entry = Mutex<Entry?>(nil)
    private let clock: ElapsedClock

    init() { clock = ElapsedClock() }

    init<C: Clock<Duration>>(clock: C) { self.clock = ElapsedClock(clock) }

    /// Remembers that deleting `record` waits for the word, replacing any earlier ask.
    func ask(for record: InsertionRecord) {
        let now = clock.nanoseconds
        entry.withLock { $0 = Entry(record: record, askedAt: now) }
    }

    /// Forgets the ask.
    func cancel() {
        entry.withLock { $0 = nil }
    }

    /// The span asked about when `record` is still that span and the window has not passed; the ask is spent either way.
    func take(matching record: InsertionRecord) -> Bool {
        let now = clock.nanoseconds
        let (seconds, attoseconds) = ConfirmationPolicy.window.components
        let window = UInt64(seconds) * 1_000_000_000 + UInt64(attoseconds / 1_000_000_000)
        return entry.withLock { entry in
            defer { entry = nil }
            guard let asked = entry else { return false }
            return asked.record == record && now - asked.askedAt <= window
        }
    }
}
