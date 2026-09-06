public import UttrflowCore

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

    /// Judges the rewrite against the kept words, the readings offered, and the echo a pass took back after it.
    public func verdict(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan] = [], echoed: String = ""
    ) -> GuardVerdict {
        if case .rejected(let reason) = verdict(original: draft.text, rewritten: rewritten) {
            return .rejected(reason: reason)
        }
        if case .rejected(let reason) = Self.candidateVerdict(doubtful, rewritten: rewritten) {
            return .rejected(reason: reason)
        }
        if case .rejected(let reason) = Self.layoutVerdict(kept: draft.text, rewritten: rewritten) {
            return .rejected(reason: reason)
        }
        return Self.grammarVerdict(
            kept: draft.text, rewritten: rewritten, allowing: doubtful, echoed: echoed)
    }

    /// A doubtful run may be written as it was heard or as a reading that was offered, and as nothing else.
    static func candidateVerdict(_ doubtful: [DoubtfulSpan], rewritten: String) -> GuardVerdict {
        let written = DoubtfulSpan.closedUp(rewritten)
        for span in doubtful
        where !([span.heard] + span.candidates).contains(where: {
            written.contains(DoubtfulSpan.closedUp($0))
        }) {
            return .rejected(reason: "the rewrite read '\(span.heard)' as a word it was not offered")
        }
        return .accepted
    }

    /// Refuses a rewrite that flattened a break the speaker asked for, since layout is the passes' to decide.
    static func layoutVerdict(kept: String, rewritten: String) -> GuardVerdict {
        let wanted = breaks(in: kept)
        let got = breaks(in: rewritten)
        guard wanted.paragraphs <= got.paragraphs, wanted.lines <= got.lines else {
            return .rejected(reason: "the rewrite dropped a line break the speaker asked for")
        }
        return .accepted
    }

    /// Paragraph breaks and line breaks, counting a paragraph as one break rather than two lines.
    private static func breaks(in text: String) -> (paragraphs: Int, lines: Int) {
        let paragraphs = text.components(separatedBy: "\n\n").count - 1
        let lines = text.filter { $0.isNewline }.count - paragraphs
        return (paragraphs, lines)
    }

    public func verdict(original: String, rewritten: String) -> GuardVerdict {
        let originalWords = Self.words(original)
        let rewrittenWords = Self.words(rewritten)

        if !originalWords.isEmpty, rewrittenWords.isEmpty {
            return .rejected(reason: "the rewrite is empty")
        }
        // A speaker who opens with "I have" gets their words, not a preamble check.
        if let preamble = Self.preambles.first(where: {
            rewritten.lowercased().hasPrefix($0) && !original.lowercased().hasPrefix($0)
        }) {
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

    // MARK: Grammar

    /// A word of the kept draft or the rewrite, carrying what the grammar checks need to classify it.
    struct GrammarToken: Sendable, Equatable {
        /// The word as written, punctuation trimmed from its edges.
        let text: String
        /// Lowercased with curly apostrophes straightened, the form the function-word set is keyed by.
        let lookup: String
        /// The lookup form with apostrophes removed, the form words are matched for survival by.
        let matching: String
        /// Whether the word opens the text or follows a sentence-closing mark.
        let startsSentence: Bool

        /// Whether the checks can read the word at all; Devanagari and the like are left to the base checks.
        var isPlain: Bool { matching.allSatisfy(\.isASCII) }
    }

    /// A repair may change a word's form, never which content words survive. See `Docs/cleanup.md`.
    static func grammarVerdict(
        kept: String, rewritten: String, allowing doubtful: [DoubtfulSpan] = [], echoed: String = ""
    ) -> GuardVerdict {
        let keptTokens = grammarTokens(kept)
        let rewrittenTokens = grammarTokens(rewritten)
        // The echo the caret pass took back was in the model's answer, so its words still count as survivors.
        let pool = Set((rewrittenTokens + grammarTokens(echoed)).filter(\.isPlain).map(\.matching))
        // A word a reading was offered for answers to the check above, a reading being by definition not what was said.
        let offered = Set(
            doubtful
                .flatMap { $0.heard.split(whereSeparator: \.isWhitespace) }
                .map { DoubtfulSpan.closedUp(String($0)) })
        for token in keptTokens
        where token.isPlain && isContent(token) && !offered.contains(DoubtfulSpan.closedUp(token.text)) {
            if !survives(token.matching, in: pool) {
                return .rejected(reason: "the rewrite lost or replaced '\(token.text)'")
            }
        }
        let dropped = negators(in: keptTokens) - negators(in: rewrittenTokens + grammarTokens(echoed))
        if dropped > 0 {
            return .rejected(reason: "the rewrite dropped a negation")
        }
        let churn = functionWordChurn(keptTokens, rewrittenTokens)
        if churn > 3 * sentenceCount(rewritten) {
            return .rejected(reason: "the rewrite changed \(churn) small words")
        }
        return .accepted
    }

    /// Splits on whitespace and hyphens, trimming punctuation and tracking sentence starts.
    static func grammarTokens(_ text: String) -> [GrammarToken] {
        var tokens: [GrammarToken] = []
        var startsSentence = true
        let pieces = withoutThousandsSeparators(text)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
        for raw in pieces {
            let endsSentence = raw.contains { ".!?".contains($0) }
            let trimmed = raw.drop(while: { !$0.isLetter && !$0.isNumber })
            let word = trimmed.reversed().drop(while: { !$0.isLetter && !$0.isNumber }).reversed()
            guard !word.isEmpty else {
                startsSentence = startsSentence || endsSentence
                continue
            }
            let lookup = String(word).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            tokens.append(
                GrammarToken(
                    text: String(word), lookup: lookup,
                    matching: lookup.replacingOccurrences(of: "'", with: ""),
                    startsSentence: startsSentence))
            startsSentence = endsSentence
        }
        return tokens
    }

    /// A number and a mid-sentence capital are always content; the rest is unless the set below holds it.
    static func isContent(_ token: GrammarToken) -> Bool {
        if token.matching.contains(where: \.isNumber) { return true }
        if !token.startsSentence, token.text.first?.isUppercase == true { return true }
        return !functionWords.contains(token.lookup)
    }

    /// Whether a content word survives: exact, as its numeral or its word, in an identifier, by stem, or as a verb form.
    static func survives(_ word: String, in pool: Set<String>) -> Bool {
        if pool.contains(word) { return true }
        if let digits = numberWords[word], pool.contains(digits) { return true }
        if word.allSatisfy(\.isNumber), pool.contains(where: { numberWords[$0] == word }) { return true }
        if pool.contains(where: { numberWords[$0] == word }) { return true }
        // A word spelled into an identifier — "invoices" inside "fetchInvoices" — is still there.
        if word.count >= 3, pool.contains(where: { $0.contains(word) }) { return true }
        let stem = word.count >= 3 ? String(word.prefix(3)) : word
        if pool.contains(where: { $0.hasPrefix(stem) }) { return true }
        if let index = IrregularVerbForms.setIndex[word] {
            return pool.contains { IrregularVerbForms.setIndex[$0] == index }
        }
        return false
    }

    /// How many words in `tokens` turn a sentence's meaning around.
    static func negators(in tokens: [GrammarToken]) -> Int {
        tokens.filter { negatingWords.contains($0.matching) }.count
    }

    /// The words that reverse a sentence, apostrophes aside; dropping one is the worst edit the model can make.
    static let negatingWords: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "nowhere", "neither", "nor", "cannot",
        "dont", "doesnt", "didnt", "wont", "wouldnt", "cant", "couldnt", "shouldnt", "isnt",
        "arent", "wasnt", "werent", "hasnt", "havent", "hadnt", "mustnt", "aint", "neednt",
    ]

    /// Function words added plus removed, counted as multisets over the whole text.
    static func functionWordChurn(_ kept: [GrammarToken], _ rewritten: [GrammarToken]) -> Int {
        func counts(_ tokens: [GrammarToken]) -> [String: Int] {
            var result: [String: Int] = [:]
            for token in tokens where token.isPlain && !isContent(token) {
                result[token.lookup, default: 0] += 1
            }
            return result
        }
        let before = counts(kept)
        let after = counts(rewritten)
        return Set(before.keys).union(after.keys).reduce(0) { $0 + abs((before[$1] ?? 0) - (after[$1] ?? 0)) }
    }

    /// Sentences in the rewrite, counted by closing marks followed by space or end, never below one.
    static func sentenceCount(_ text: String) -> Int {
        let characters = Array(text)
        var count = 0
        for (index, character) in characters.enumerated() where ".!?".contains(character) {
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            if next.isWhitespace || next == "\"" { count += 1 }
        }
        return max(1, count)
    }

    /// Articles, prepositions, conjunctions, auxiliaries, pronouns and "not"; dialect stays content.
    static let functionWords: Set<String> = [
        "a", "an", "the",
        "of", "in", "on", "at", "to", "for", "with", "by", "from", "about", "into", "onto", "over",
        "under", "after", "before", "between", "through", "during", "against", "among", "without",
        "within", "along", "across", "behind", "beyond", "near", "up", "down", "off", "out", "around",
        "past", "since", "until", "till", "upon", "toward", "towards", "per",
        "and", "or", "but", "nor", "so", "yet", "because", "although", "though", "while", "if",
        "unless", "than", "whether", "that", "as", "when", "where", "once",
        "am", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has",
        "had", "having", "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        "ought", "not",
        "don't", "doesn't", "didn't", "won't", "wouldn't", "can't", "couldn't", "shouldn't", "isn't",
        "aren't", "wasn't", "weren't", "hasn't", "haven't", "hadn't", "mustn't", "ain't",
        "dont", "doesnt", "didnt", "wont", "wouldnt", "cant", "couldnt", "shouldnt", "isnt", "arent",
        "wasnt", "werent", "hasnt", "havent", "hadnt", "aint",
        "i'll", "i'm", "i've", "i'd", "he'll", "she'll", "we'll", "they'll", "you'll", "it'll",
        "it's", "that's", "there's", "here's", "what's", "who's", "let's", "you're", "we're",
        "they're", "you've", "we've", "they've", "you'd", "we'd", "they'd", "he'd", "she'd",
        "im", "ive", "youre", "theyre", "youve", "weve", "theyve", "thats", "theres",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your",
        "his", "its", "our", "their", "mine", "yours", "hers", "ours", "theirs", "this", "these",
        "those", "there", "who", "whom", "whose", "which", "what", "myself", "yourself", "himself",
        "herself", "itself", "ourselves", "yourselves", "themselves",
    ]

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
            withoutThousandsSeparators(text).split(whereSeparator: { !$0.isNumber })
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    /// Drops a comma that groups digits, so "12,000" and "1,50,000" read as the numbers they are.
    static func withoutThousandsSeparators(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            if character == ",", index > 0, characters[index - 1].isNumber {
                let run = characters[(index + 1)...].prefix(while: \.isNumber).count
                if run == 2 || run == 3 { continue }
            }
            result.append(character)
        }
        return result
    }

    /// Digits the speaker uttered as words. Covers what people dictate in practice —
    /// times, counts and short quantities — rather than every possible numeral.
    ///
    /// Hindi is here, in both scripts, because it has to be: a Hindi speaker saying
    /// "बीस मिनट" gets "20 minute", and with only English words in this table the
    /// guard called that an invented number and threw the rewrite away. Every Hindi
    /// utterance containing a number failed that way.
    /// A word in both tables traps on the first lookup rather than letting one language quietly win.
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
