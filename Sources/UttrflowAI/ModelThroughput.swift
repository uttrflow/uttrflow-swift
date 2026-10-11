import Synchronization

/// How fast one model has recently answered, so a loaded Mac gets a longer allowance instead of the raw text.
public final class ModelThroughput: Sendable {
    /// How many recent answers are kept; the slowest of them sets the pace.
    static let window = 8
    /// The fewest words an answer is counted as, so a short piece's fixed start-up cost is not read as a per-word rate.
    static let minimumCountedWords = 20

    private let samples = Mutex<[Duration]>([])

    public init() {}

    /// Counts one answered request of `words` words that took `elapsed`.
    public func record(words: Int, elapsed: Duration) {
        guard elapsed > .zero else { return }
        let perWord = elapsed / max(words, Self.minimumCountedWords)
        samples.withLock { kept in
            kept.append(perWord)
            if kept.count > Self.window { kept.removeFirst(kept.count - Self.window) }
        }
    }

    /// The slowest recent time per word, or nil before any answer has been measured.
    public var timePerWord: Duration? {
        samples.withLock { $0.max() }
    }
}
