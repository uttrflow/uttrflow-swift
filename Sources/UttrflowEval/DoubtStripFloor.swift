// Whether a word score clears the floor a strip of doubtful words must clear before it is built.

/// The floor from `Docs/ai-correction-thresholds.md`, and the score's recall and precision at its flag budget.
public enum DoubtStripFloor {
    /// At most this many flags per 100 words.
    public static let flagsPerHundred = 3
    /// The share of wrong words the flags must catch.
    public static let recallFloor = 0.5
    /// The share of flags that must be wrong words.
    public static let precisionFloor = 0.5

    /// The score's result when the lowest-scored words are flagged, up to the budget.
    public struct Result: Sendable, Equatable {
        public let words: Int
        public let flags: Int
        /// Wrong words that are flagged, over all wrong words.
        public let recall: GroupCalibration.Share
        /// Flags that are wrong words, over all flags.
        public let precision: GroupCalibration.Share
        /// Wrong words with no score at all, which no flag can reach.
        public let unflaggable: GroupCalibration.Share

        /// Whether both point estimates reach their floors.
        public var clears: Bool {
            flags > 0 && recall.value >= DoubtStripFloor.recallFloor
                && precision.value >= DoubtStripFloor.precisionFloor
        }
    }

    /// Flags the lowest-scored words, at most `flagsPerHundred` per 100 words, and measures them.
    public static func evaluate(_ words: [ScoredWord], flagsPerHundred: Int = flagsPerHundred) -> Result {
        let errors = words.count { !$0.isRight }
        let scored = words.compactMap { word in word.score.map { (score: $0, isRight: word.isRight) } }
        let budget = words.count * flagsPerHundred / 100
        let flagged = scored.sorted { $0.score < $1.score }.prefix(budget)
        let caught = flagged.count { !$0.isRight }
        let unscored = words.count { $0.score == nil && !$0.isRight }
        return Result(
            words: words.count, flags: flagged.count,
            recall: GroupCalibration.Share(count: caught, total: errors),
            precision: GroupCalibration.Share(count: caught, total: flagged.count),
            unflaggable: GroupCalibration.Share(count: unscored, total: errors))
    }

    /// One line stating the result against the floor.
    public static func summary(_ result: Result) -> String {
        func percent(_ share: GroupCalibration.Share) -> String {
            guard share.total > 0 else { return "n/a" }
            let range = share.interval
            return "\(share.count)/\(share.total) "
                + "(\(Int((share.value * 100).rounded()))%, "
                + "\(Int((range.lowerBound * 100).rounded()))–\(Int((range.upperBound * 100).rounded())))"
        }
        return
            "Strip floor at \(flagsPerHundred) per 100 (\(result.flags) flags over \(result.words) words): "
            + "recall \(percent(result.recall)), precision \(percent(result.precision)), "
            + "unflaggable \(percent(result.unflaggable)); "
            + (result.clears ? "clears" : "does not clear")
    }
}
