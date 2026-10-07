// The one rule for whether a heard word is doubted, which every consumer of doubt asks.
import UttrflowCore
import UttrflowDictionary

/// Whether a word is doubted and why; the engine, the rules, the doubtful-words prompt and the guard all ask it. See Docs/cleanup.md.
public enum DoubtPolicy {
    /// Below this a word may be replaced; at or above it a word may corroborate, so none vouches for itself.
    public static let certaintyThreshold = 0.5

    /// Whether the recogniser scored a word surely enough to corroborate and to refuse a sound-alike swap.
    public static func isHeardSurely(_ confidence: Double) -> Bool {
        confidence >= certaintyThreshold
    }

    /// Whether no later layer may rewrite the word: an override settled it, or the recogniser heard it surely.
    public static func isProtected(confidence: Double, settled: Bool) -> Bool {
        settled || isHeardSurely(confidence)
    }

    /// Why one word is doubted, or `nil` when it is not: never a settled word, then a low score, else a homophone group.
    public static func reason(text: String, confidence: Double, settled: Bool = false) -> DoubtReason? {
        guard !settled else { return nil }
        if !isHeardSurely(confidence) { return .lowScore }
        return Homophones.group(containing: text) == nil ? nil : .homophoneClass
    }

    /// How much the destination raises a wrong word's cost: kept for review, sent or opened, or run.
    static func severity(of consequence: Consequence) -> Int {
        switch consequence {
        case .stores: 0
        case .sends, .navigates: 1
        case .executes: 2
        }
    }

    /// Whether a pass may replace a heard word; a costlier error needs more evidence, so the override rate never rises with cost.
    public enum OverridePolicy {
        /// Signals a candidate needs beyond the heard reading at the cheapest tier; two, so one coincidence never swaps a homophone.
        public static let baseMargin = 2

        /// The evidence margin a candidate must win by for this pair and destination.
        static func requiredMargin(cost: ConfusionCost, consequence: Consequence) -> Int {
            baseMargin + cost.rawValue + severity(of: consequence)
        }

        /// Whether a candidate that won by `margin` signals may replace the heard word.
        static func allows(margin: Int, cost: ConfusionCost, consequence: Consequence) -> Bool {
            margin >= requiredMargin(cost: cost, consequence: consequence)
        }
    }

    /// Whether the user is shown that a word may be wrong; a costlier error is flagged on less doubt, so the flag rate never falls with cost.
    public enum FlagPolicy {
        /// How far each step of cost lifts the flag line above the certainty threshold; provisional until per-pair error is measured.
        public static let stepPerTier = 0.1

        /// Below this confidence the word is flagged for this pair and destination.
        static func flagLine(cost: ConfusionCost, consequence: Consequence) -> Double {
            min(1, certaintyThreshold + stepPerTier * Double(cost.rawValue + severity(of: consequence)))
        }

        /// Whether a word heard at `confidence` is flagged for review.
        static func flags(confidence: Double, cost: ConfusionCost, consequence: Consequence) -> Bool {
            confidence < flagLine(cost: cost, consequence: consequence)
        }
    }
}
