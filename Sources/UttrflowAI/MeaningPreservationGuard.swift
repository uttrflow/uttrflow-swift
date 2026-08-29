/// Whether a rewrite may be shown to the user.
public enum GuardVerdict: Sendable, Equatable {
    case accepted
    case rejected(reason: String)

    public var isAccepted: Bool { self == .accepted }
}

/// Checks that a language model tidied the words rather than replacing them.
///
/// §9 of the requirements is that meaning must not change. A small on-device model
/// breaks that in specific, observable ways — it answers a dictated question, it obeys
/// a dictated instruction, it prefixes "Here is the text:" — all of which were seen
/// while building this. Each check below exists because a real model did the thing it
/// catches.
public struct MeaningPreservationGuard: Sendable {
    /// A rewrite may grow — punctuation, expanded contractions — but not by this much.
    private static let maximumGrowthFactor = 2.0
    /// Below this fraction of the original words, the model has replaced rather than
    /// tidied. Tuned to allow heavy filler removal from a short utterance.
    private static let minimumRetainedFraction = 0.4
    /// Short utterances are exempt from the retention floor: "um yes" legitimately
    /// becomes "Yes." Kept deliberately low — at six, "what is the capital of france"
    /// was exempt, and the model answering it with "Paris" slipped through.
    private static let shortUtteranceWords = 3

    private static let preambles = [
        "here is", "here's", "sure,", "certainly", "of course", "i've", "i have",
        "the corrected", "the cleaned", "cleaned:", "output:", "result:",
    ]

    public init() {}

    public func verdict(original: String, rewritten: String) -> GuardVerdict {
        let originalWords = Self.words(original)
        let rewrittenWords = Self.words(rewritten)

        if !originalWords.isEmpty, rewrittenWords.isEmpty {
            return .rejected(reason: "the rewrite is empty")
        }
        if let preamble = Self.preambles.first(where: rewritten.lowercased().hasPrefix) {
            return .rejected(reason: "the rewrite begins with '\(preamble)'")
        }
        if Double(rewrittenWords.count) > Double(originalWords.count) * Self.maximumGrowthFactor + 4 {
            return .rejected(reason: "the rewrite is far longer than what was said")
        }
        if originalWords.count > Self.shortUtteranceWords {
            let retained = Double(rewrittenWords.count) / Double(originalWords.count)
            if retained < Self.minimumRetainedFraction {
                return .rejected(reason: "the rewrite dropped most of what was said")
            }
        }
        if let invented = Self.inventedNumber(original: original, rewritten: rewritten) {
            return .rejected(reason: "the rewrite introduced the number \(invented)")
        }
        return .accepted
    }

    // MARK: Checks

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// A number in the rewrite that was not in what was said.
    ///
    /// Spelled-out numbers are normalised first, because turning "twenty" into "20" is
    /// exactly the kind of tidying this product is for — only a *new* number is a lie.
    static func inventedNumber(original: String, rewritten: String) -> String? {
        let spoken = numbers(in: original).union(spelledNumbers(in: original))
        return numbers(in: rewritten).subtracting(spoken).min()
    }

    private static func numbers(in text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: { !$0.isNumber })
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    /// Digits the speaker uttered as words. Covers what people dictate in practice —
    /// times, counts and short quantities — rather than every possible numeral.
    ///
    /// Hindi is here, in both scripts, because it has to be: a Hindi speaker saying
    /// "बीस मिनट" gets "20 minute", and with only English words in this table the
    /// guard called that an invented number and threw the rewrite away. Every Hindi
    /// utterance containing a number failed that way.
    /// Built so that a word appearing in both tables is a build-time-fatal mistake
    /// rather than a silent winner: the two languages must not disagree about a digit.
    private static let numberWords: [String: String] = Dictionary(
        uniqueKeysWithValues: Array(englishNumberWords) + Array(hindiNumberWords))

    private static let hindiNumberWords: [String: String] = [
        "एक": "1", "ek": "1",
        "दो": "2", "do": "2",
        "तीन": "3", "teen": "3", "tin": "3",
        "चार": "4", "char": "4", "chaar": "4",
        "पांच": "5", "पाँच": "5", "paanch": "5", "panch": "5",
        "छह": "6", "छे": "6", "chhe": "6", "chah": "6",
        "सात": "7", "saat": "7", "sat": "7",
        "आठ": "8", "aath": "8", "ath": "8",
        "नौ": "9", "nau": "9",
        "दस": "10", "das": "10",
        "ग्यारह": "11", "gyarah": "11",
        "बारह": "12", "barah": "12",
        "पंद्रह": "15", "pandrah": "15",
        "बीस": "20", "bees": "20", "bis": "20",
        "तीस": "30", "tees": "30",
        "चालीस": "40", "chalis": "40",
        "पचास": "50", "pachas": "50",
        "सौ": "100", "sau": "100",
        "हज़ार": "1000", "हजार": "1000", "hazaar": "1000", "hazar": "1000",
    ]

    private static let englishNumberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14",
        "fifteen": "15", "sixteen": "16", "seventeen": "17", "eighteen": "18",
        "nineteen": "19", "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50",
        "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
        "hundred": "100", "thousand": "1000",
    ]

    private static func spelledNumbers(in text: String) -> Set<String> {
        Set(words(text).compactMap { numberWords[$0] })
    }
}
