// A back-off n-gram language model of order at most 3, held as interned word ids for constant-time lookup.

/// One n-gram's log10 probability and the log10 back-off weight applied when a longer n-gram is missing.
public struct NGramEntry: Sendable, Equatable {
    /// The log10 probability of the last word given the words before it.
    public let log10Probability: Float
    /// The log10 weight added when backing off from this history; 0 when the file gives none.
    public let log10Backoff: Float

    public init(log10Probability: Float, log10Backoff: Float = 0) {
        self.log10Probability = log10Probability
        self.log10Backoff = log10Backoff
    }
}

/// A back-off n-gram model read from an ARPA file, scored with the standard back-off recursion.
public struct NGramModel: Sendable {
    /// The highest order this model type holds.
    public static let maxOrder = 3
    /// The log10 probability of a word the model has never seen and that has no `<unk>` entry.
    public static let unseenLog10Probability: Float = -10
    /// The largest number of distinct words, since each id takes 21 bits of a packed key.
    public static let maxVocabulary = (1 << 21) - 2
    static let unknownToken = "<unk>"

    /// The order of the longest n-grams in the model.
    public let order: Int
    private let ids: [String: UInt32]
    private let entries: [UInt64: NGramEntry]

    init(order: Int, ids: [String: UInt32], entries: [UInt64: NGramEntry]) {
        self.order = order
        self.ids = ids
        self.entries = entries
    }

    /// The number of distinct words in the model.
    public var vocabularyCount: Int { ids.count }
    /// The number of n-grams of every order in the model.
    public var nGramCount: Int { entries.count }

    /// The log10 probability of `word` following `history`, of which only the last `order - 1` words count.
    public func log10Probability(of word: String, after history: [String]) -> Float {
        guard let wordID = id(of: word) else { return Self.unseenLog10Probability }
        let historyIDs = history.suffix(order - 1).map { ids[$0] ?? 0 }
        return backedOff(wordID, Array(historyIDs))
    }

    private func id(of word: String) -> UInt32? {
        ids[word] ?? ids[Self.unknownToken]
    }

    func backedOff(_ word: UInt32, _ history: [UInt32]) -> Float {
        var history = history
        var backoff: Float = 0
        while true {
            if let entry = entries[Self.key(history + [word])] {
                return backoff + entry.log10Probability
            }
            guard !history.isEmpty else { return Self.unseenLog10Probability }
            backoff += entries[Self.key(history)]?.log10Backoff ?? 0
            history.removeFirst()
        }
    }

    /// Packs up to three word ids into one key; an id of 0 is a word outside the model, which matches no entry.
    static func key(_ wordIDs: [UInt32]) -> UInt64 {
        guard !wordIDs.contains(0) else { return 0 }
        return wordIDs.reduce(UInt64(0)) { ($0 << 21) | UInt64($1) }
    }
}
