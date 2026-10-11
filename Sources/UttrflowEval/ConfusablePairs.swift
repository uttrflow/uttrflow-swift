// The confusable pairs whose error costs most, held as data so their error rate can be measured per pair.
private import UttrflowCore

/// Two readings of one invented sentence that differ in one slot, the second the likely misreading of the first.
public struct ConfusablePair: Sendable, Equatable {
    /// Why the pair is in the inventory; the cost class itself is `ConfusionCost`'s, never this list's.
    public enum Group: String, Sendable, Equatable, CaseIterable {
        /// One reading negates and the other does not: "can" and "can't", a dropped "not".
        case negation
        /// Romanised Hindi or Hinglish negation: "nahi", "mat", "na", present or dropped.
        case hindiNegation
        /// A teen and its ten: "fifteen" and "fifty".
        case teenTen
        /// An amount and a near word: "hundred" and "thousand", "two" and "to", "a" and "one".
        case nearQuantity
        /// Words a recogniser swaps whose swap turns the meaning: "accept" and "except".
        case meaningSwap
    }

    /// Why the pair is listed.
    public let group: Group
    /// The sentence with `_` where the two readings differ.
    public let carrier: String
    /// The word or words in the slot for the first reading.
    public let first: String
    /// The slot for the second reading; empty when the misreading drops the word.
    public let second: String

    /// A pair read in `carrier` with `first` or `second` in its slot.
    public init(_ group: Group, _ carrier: String, _ first: String, _ second: String) {
        self.group = group
        self.carrier = carrier
        self.first = first
        self.second = second
    }

    /// The first reading as a sentence.
    public var firstReading: String { reading(first) }

    /// The second reading as a sentence.
    public var secondReading: String { reading(second) }

    private func reading(_ slot: String) -> String {
        carrier.split(separator: " ", omittingEmptySubsequences: true)
            .flatMap { $0 == "_" ? slot.split(separator: " ") : [$0] }
            .joined(separator: " ")
    }
}

/// The inventory, the outcome of one decode, and the counts a row of the table reports. See Docs/eval-methodology.md.
public enum ConfusablePairs {
    /// Every pair, each read both ways when measured.
    public static let all: [ConfusablePair] = negation + hindiNegation + teenTen + nearQuantity + meaningSwap

    static let negation: [ConfusablePair] = [
        ConfusablePair(.negation, "we _ ship the update today", "can", "can't"),
        ConfusablePair(.negation, "the build _ pass on the old laptop", "will", "won't"),
        ConfusablePair(.negation, "she _ reply to the invite", "did", "didn't"),
        ConfusablePair(.negation, "the side door _ locked when I left", "was", "wasn't"),
        ConfusablePair(.negation, "we _ find the spare keys", "could", "couldn't"),
        ConfusablePair(.negation, "please _ send the draft yet", "do", "don't"),
        ConfusablePair(.negation, "the review is _ due on friday", "now", "not"),
        ConfusablePair(.negation, "the tests are _ passing on the branch", "not", ""),
    ]

    static let hindiNegation: [ConfusablePair] = [
        ConfusablePair(.hindiNegation, "main kal office _ aaunga", "nahi", ""),
        ConfusablePair(.hindiNegation, "abhi yeh file _ bhejo", "mat", ""),
        ConfusablePair(.hindiNegation, "usne kuch _ kaha", "na", ""),
        ConfusablePair(.hindiNegation, "the build abhi _ chal raha", "nahi", ""),
    ]

    static let teenTen: [ConfusablePair] = [
        ConfusablePair(.teenTen, "we need _ chairs for the hall", "thirteen", "thirty"),
        ConfusablePair(.teenTen, "the train leaves in _ minutes", "fourteen", "forty"),
        ConfusablePair(.teenTen, "order _ boxes of paper", "fifteen", "fifty"),
        ConfusablePair(.teenTen, "the file has _ pages", "sixteen", "sixty"),
        ConfusablePair(.teenTen, "the parcel weighs _ kilos", "seventeen", "seventy"),
        ConfusablePair(.teenTen, "the room holds _ people", "eighteen", "eighty"),
        ConfusablePair(.teenTen, "move the meeting by _ days", "nineteen", "ninety"),
    ]

    static let nearQuantity: [ConfusablePair] = [
        ConfusablePair(.nearQuantity, "the hall seats a _ guests", "hundred", "thousand"),
        ConfusablePair(.nearQuantity, "the fund raised a _ dollars", "million", "billion"),
        ConfusablePair(.nearQuantity, "I ordered _ coffee for the desk", "a", "one"),
        ConfusablePair(.nearQuantity, "it was _ honest mistake", "an", "a"),
        ConfusablePair(.nearQuantity, "the porch light stayed _ all night", "on", "one"),
        ConfusablePair(.nearQuantity, "add _ eggs to the bowl", "two", "to"),
        ConfusablePair(.nearQuantity, "we need _ more chairs", "four", "for"),
        ConfusablePair(.nearQuantity, "we _ at the hotel", "ate", "eight"),
    ]

    static let meaningSwap: [ConfusablePair] = [
        ConfusablePair(.meaningSwap, "we _ all the changes", "accept", "except"),
        ConfusablePair(.meaningSwap, "the new cache will _ the speed", "affect", "effect"),
        ConfusablePair(.meaningSwap, "do not _ the receipt", "lose", "loose"),
    ]

    /// What the recogniser wrote for one reading.
    public enum Outcome: String, Sendable, Equatable, CaseIterable {
        /// It wrote the reading that was spoken.
        case right
        /// It wrote something nearer the other reading than the spoken one: the costly confusion.
        case flipped
        /// It wrote something wrong that is no nearer the other reading.
        case otherError
    }

    /// Reads normalised words: right when they equal `meant`, flipped when they are fewer edits from `other`.
    public static func outcome(meant: [String], other: [String], heard: [String]) -> Outcome {
        if heard == meant { return .right }
        let toMeant = WordErrorRate.measure(reference: meant, hypothesis: heard).errors
        let toOther = WordErrorRate.measure(reference: other, hypothesis: heard).errors
        return toOther < toMeant ? .flipped : .otherError
    }

    /// The counts one row reports.
    public struct Tally: Sendable, Equatable {
        /// Decodes counted.
        public private(set) var decodes = 0
        /// Decodes that wrote the other reading.
        public private(set) var flips = 0
        /// Decodes wrong in some other way.
        public private(set) var otherErrors = 0

        /// An empty tally.
        public init() {}

        /// Counts one decode.
        public mutating func add(_ outcome: Outcome) {
            decodes += 1
            switch outcome {
            case .right: break
            case .flipped: flips += 1
            case .otherError: otherErrors += 1
            }
        }

        /// Decodes that wrote the other reading, over decodes.
        public var flipRate: Double { decodes == 0 ? 0 : Double(flips) / Double(decodes) }

        /// Decodes that wrote anything but the spoken reading, over decodes.
        public var errorRate: Double { decodes == 0 ? 0 : Double(flips + otherErrors) / Double(decodes) }
    }
}
