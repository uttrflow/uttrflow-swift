public import UttrflowCore

// The verdict on a rewrite, and the guard that reaches it.
/// Whether a rewrite may be shown to the user.
public enum GuardVerdict: Sendable, Equatable {
    /// The rewrite may be shown.
    case accepted
    /// The rewrite is refused, with the reason a log can show.
    case rejected(reason: String)

    public var isAccepted: Bool { self == .accepted }
}

/// Checks that a model tidied the words rather than replacing them. See Docs/ai-model-output.md.
public struct MeaningPreservationGuard: Sendable {
    /// A rewrite may grow — punctuation, expanded contractions — but not by this much.
    private static let maximumGrowthFactor = 2.0
    /// Below this fraction of the original words the model replaced rather than tidied.
    private static let minimumRetainedFraction = 0.4
    /// Utterances this short skip the retention floor ("um yes" to "Yes."); at six, "Paris" slipped through.
    private static let shortUtteranceWords = 3

    /// Openings that mean the model is chatting rather than tidying.
    private static let preambles = [
        "here is", "here's", "sure,", "certainly", "of course", "i've", "i have",
        "the corrected", "the cleaned", "cleaned:", "output:", "result:",
    ]

    /// Makes a guard; it holds no state.
    public init() {}

    /// Judges the rewrite against the kept words, the readings offered, and the echo a pass took back after it.
    public func verdict(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan] = [], echoed: String = ""
    ) -> GuardVerdict {
        if case .rejected(let reason) = verdict(original: draft.text, rewritten: rewritten) {
            return .rejected(reason: reason)
        }
        let alignment = RewriteAlignment(kept: draft.text, rewritten: rewritten)
        let readings = Self.readingVerdict(doubtful, in: alignment)
        if case .rejected(let reason) = readings.verdict {
            return .rejected(reason: reason)
        }
        if case .rejected(let reason) = Self.layoutVerdict(kept: draft.text, rewritten: rewritten) {
            return .rejected(reason: reason)
        }
        return Self.grammarVerdict(alignment, excusing: readings.excused, echoed: echoed)
    }

    /// A doubtful run may be written where it stands as it was heard or as a reading offered for it, and as nothing else.
    static func readingVerdict(
        _ doubtful: [DoubtfulSpan], in alignment: RewriteAlignment
    ) -> (verdict: GuardVerdict, excused: Set<Int>) {
        var excused: Set<Int> = []
        guard !doubtful.isEmpty else { return (.accepted, excused) }
        for span in doubtful {
            for place in alignment.keptRuns(spelled: DoubtfulSpan.closedUp(span.heard)) {
                let touched = alignment.changes.filter { $0.kept.overlaps(place) }
                // A run the rewrite left where it stood is the run as it was heard, and needs no reading.
                guard let first = touched.first, let last = touched.last else { continue }
                let start = min(place.lowerBound, first.kept.lowerBound)
                let end = max(place.upperBound, last.kept.upperBound)
                // A change reaching past the run took its neighbours with it, so they are expected here too.
                let before = alignment.keptSpelling(of: start..<place.lowerBound)
                let after = alignment.keptSpelling(of: place.upperBound..<end)
                let offered = ([span.heard] + span.candidates).map {
                    before + DoubtfulSpan.closedUp($0) + after
                }
                guard offered.contains(alignment.standing(in: start..<end)) else {
                    let reason = "the rewrite read '\(span.heard)' as a word it was not offered"
                    return (.rejected(reason: reason), excused)
                }
                // A reading rightly written here is the one substitution the survival check must let past.
                for change in touched { excused.formUnion(change.kept.clamped(to: place)) }
            }
        }
        return (.accepted, excused)
    }

    /// The same judgement over two texts, which is how a test states one.
    static func candidateVerdict(
        _ doubtful: [DoubtfulSpan], kept: String, rewritten: String
    ) -> GuardVerdict {
        readingVerdict(doubtful, in: RewriteAlignment(kept: kept, rewritten: rewritten)).verdict
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

    /// Accepts a rewrite unless it is empty, chatty, far longer, mostly dropped, or invents a number.
    public func verdict(original: String, rewritten: String) -> GuardVerdict {
        let originalWords = TextTidy.words(original)
        let rewrittenWords = TextTidy.words(rewritten)

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
        let alignment = RewriteAlignment(kept: kept, rewritten: rewritten)
        return grammarVerdict(
            alignment, excusing: readingVerdict(doubtful, in: alignment).excused, echoed: echoed)
    }

    /// The same check over an alignment already in hand, each word judged against what stands in its own place.
    static func grammarVerdict(
        _ alignment: RewriteAlignment, excusing excused: Set<Int>, echoed: String
    ) -> GuardVerdict {
        let echoTokens = grammarTokens(echoed)
        // The echo the caret pass took back was in the model's answer, so its words still count as survivors.
        let echo = Set(echoTokens.filter(\.isPlain).map(\.matching))
        for change in alignment.changes {
            let here = alignment.rewrittenWords(of: change.rewritten).union(echo)
            for index in change.kept where !excused.contains(index) {
                let token = alignment.kept[index]
                guard token.isPlain, isContent(token), !survives(token.matching, in: here) else {
                    continue
                }
                return .rejected(reason: "the rewrite lost or replaced '\(token.text)'")
            }
        }
        let dropped = negators(in: alignment.kept) - negators(in: alignment.rewritten + echoTokens)
        if dropped > 0 {
            return .rejected(reason: "the rewrite dropped a negation")
        }
        let churn = functionWordChurn(alignment.kept, alignment.rewritten)
        if churn > 3 * sentenceCount(alignment.rewrittenText) {
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

    /// The first number the rewrite states that the speaker did not state, there and that many times, or nil.
    static func inventedNumber(original: String, rewritten: String) -> String? {
        var spoken = numberSequence(in: original, readingWords: true)[...]
        for number in numberSequence(in: rewritten, readingWords: false) {
            guard let found = spoken.firstIndex(of: number) else { return number }
            spoken = spoken[(found + 1)...]
        }
        return nil
    }

    /// The numbers a text states, in order and with repeats kept, reading them as words too when asked.
    static func numberSequence(in text: String, readingWords: Bool) -> [String] {
        var found: [String] = []
        var run = ""
        var runIsDigits = false
        func flush() {
            defer { run = "" }
            guard !run.isEmpty else { return }
            if runIsDigits {
                found.append(run)
            } else if readingWords, let digits = numberWords[run.lowercased()] {
                found.append(digits)
            }
        }
        for character in withoutThousandsSeparators(text) {
            guard character.isNumber || character.isLetter else {
                flush()
                continue
            }
            if character.isNumber != runIsDigits { flush() }
            runIsDigits = character.isNumber
            run.append(character)
        }
        flush()
        return found
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

    /// Digits people dictate as words, in English and Hindi; traps on first use if the tables share a word.
    private static let numberWords: [String: String] = Dictionary(
        uniqueKeysWithValues: Array(englishNumberWords) + Array(hindiNumberWords))

    /// Hindi number words in both scripts, without which every Hindi utterance with a number fails the guard.
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

    /// The English number words people dictate in practice: times, counts and short quantities.
    private static let englishNumberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14",
        "fifteen": "15", "sixteen": "16", "seventeen": "17", "eighteen": "18",
        "nineteen": "19", "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50",
        "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
        "hundred": "100", "thousand": "1000",
    ]
}
