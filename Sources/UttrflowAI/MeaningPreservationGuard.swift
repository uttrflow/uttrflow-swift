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
        for span in doubtful
        where !([span.heard] + span.candidates).contains(where: { isWritten($0, in: rewritten) }) {
            return .rejected(reason: "the rewrite read '\(span.heard)' as a word it was not offered")
        }
        return .accepted
    }

    /// Whether a reading is written out in whole words: `PaymentSheet` for "payment sheet", never "our time" inside "four times".
    static func isWritten(_ reading: String, in rewritten: String) -> Bool {
        let wanted = Array(DoubtfulSpan.closedUp(reading))
        guard !wanted.isEmpty else { return false }
        // Closing a run up loses the spaces a word ends at, so the places words end at are kept beside it.
        var written: [Character] = []
        var edges: Set<Int> = [0]
        for word in rewritten.split(whereSeparator: \.isWhitespace) {
            written += DoubtfulSpan.closedUp(String(word))
            edges.insert(written.count)
        }
        guard written.count >= wanted.count else { return false }
        return (0...(written.count - wanted.count)).contains { start in
            edges.contains(start) && edges.contains(start + wanted.count)
                && Array(written[start..<start + wanted.count]) == wanted
        }
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

    /// A repair may change a word's form, never which content words survive or the order they came in. See `Docs/cleanup.md`.
    static func grammarVerdict(
        kept: String, rewritten: String, allowing doubtful: [DoubtfulSpan] = [], echoed: String = ""
    ) -> GuardVerdict {
        let keptTokens = grammarTokens(kept)
        let rewrittenTokens = grammarTokens(rewritten)
        // The echo the caret pass took back opened the model's answer, so its words count as survivors ahead of the rest.
        let written = (grammarTokens(echoed) + rewrittenTokens).filter(\.isPlain)
        // A word a reading was offered for answers to the check above, a reading being by definition not what was said.
        let offered = Set(
            doubtful
                .flatMap { $0.heard.split(whereSeparator: \.isWhitespace) }
                .map { DoubtfulSpan.closedUp(String($0)) })
        let carried = keptTokens.filter {
            $0.isPlain && isContent($0) && !offered.contains(DoubtfulSpan.closedUp($0.text))
        }
        if case .rejected(let reason) = survivalVerdict(carried, in: written) {
            return .rejected(reason: reason)
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
        return !FunctionWords.holds(token.lookup)
    }

    /// Walks the kept content words along the rewrite, so a word may change its form but never its place.
    static func survivalVerdict(_ kept: [GrammarToken], in written: [GrammarToken]) -> GuardVerdict {
        var reached = 0
        for token in kept {
            let places = written.indices.filter { survives(token.matching, as: written[$0]) }
            guard !places.isEmpty else {
                return .rejected(reason: "the rewrite lost or replaced '\(token.text)'")
            }
            // The earliest place still open is taken, which is the most room the words after it can be left.
            guard let place = places.first(where: { $0 >= reached }) else {
                return .rejected(reason: "the rewrite moved '\(token.text)'")
            }
            reached = place
        }
        return .accepted
    }

    /// Whether one rewritten word is the kept word: exact, as its numeral or its word, in an identifier, by stem, or as a verb form.
    static func survives(_ word: String, as candidate: GrammarToken) -> Bool {
        if word == candidate.matching { return true }
        if numberWords[word] == candidate.matching { return true }
        if numberWords[candidate.matching] == word { return true }
        if sameForm(word, candidate.matching) { return true }
        // A word spelled into an identifier — "invoices" inside "fetchInvoices" — is still there.
        if spelledInto(word, candidate.text) { return true }
        if let index = IrregularVerbForms.setIndex[word] {
            return IrregularVerbForms.setIndex[candidate.matching] == index
        }
        return false
    }

    /// Whether two words are one word in two forms: the same word, or one of them inflected from the other.
    static func sameForm(_ word: String, _ other: String) -> Bool {
        word == other || inflections(of: word).contains(other) || inflections(of: other).contains(word)
    }

    /// The forms speech inflects a word into: plural, third person, past and progressive.
    static func inflections(of word: String) -> Set<String> {
        guard word.count >= 3 else { return [] }
        var forms: Set<String> = [word + "s", word + "es", word + "ed", word + "d", word + "ing"]
        let trunk = String(word.dropLast())
        if trunk.count >= 3, word.hasSuffix("y") { forms.formUnion([trunk + "ies", trunk + "ied"]) }
        if trunk.count >= 3, word.hasSuffix("e") { forms.formUnion([trunk + "ed", trunk + "ing"]) }
        // A final consonant doubles before the ending it carries: "stop" becomes "stopped", "run" "running".
        if let last = word.last, last.isLetter, !"aeiou".contains(last) {
            forms.formUnion([word + String(last) + "ed", word + String(last) + "ing"])
        }
        return forms
    }

    /// Whether `word` is spelled into an identifier as one of its words — "invoices" in "fetchInvoices", never "ravi" in "gravity".
    static func spelledInto(_ word: String, _ identifier: String) -> Bool {
        guard word.count >= 3 else { return false }
        let written = Array(identifier)
        let lowered = Array(identifier.lowercased())
        let wanted = Array(word)
        guard lowered.count == written.count, lowered.count > wanted.count else { return false }
        return (0...(lowered.count - wanted.count)).contains { start in
            let end = start + wanted.count
            guard Array(lowered[start..<end]) == wanted else { return false }
            let opens = start == 0 || written[start].isUppercase || !written[start - 1].isLetter
            let closes = end == written.count || written[end].isUppercase || !written[end].isLetter
            return opens && closes
        }
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

    // MARK: Checks

    /// A number in the rewrite the speaker said neither in digits nor in words, or nil.
    static func inventedNumber(original: String, rewritten: String) -> String? {
        let spoken = numbers(in: original).union(spelledNumbers(in: original))
        return numbers(in: rewritten).subtracting(spoken).min()
    }

    /// Every run of digits in the text.
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

    /// The digits for every number word in the text.
    private static func spelledNumbers(in text: String) -> Set<String> {
        Set(TextTidy.words(text).compactMap { numberWords[$0] })
    }
}
