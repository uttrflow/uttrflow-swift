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
        return Self.grammarVerdict(
            alignment, excusing: readings.excused, echoed: echoed, allowing: doubtful)
    }

    /// A doubtful run may be written where it stands as it was heard or as a reading offered for it, inflected or not, and as nothing else.
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
                // The rewrite may inflect the run it was given — "payment sheets" for "payment sheet" — and change it no further.
                let offered = ([span.heard] + span.candidates).flatMap { reading in
                    let wanted = DoubtfulSpan.closedUp(reading)
                    return inflections(of: wanted).union([wanted]).map { before + $0 + after }
                }
                guard offered.contains(alignment.standing(in: start..<end)) else {
                    return (
                        .rejected(reason: "the rewrite read '\(span.heard)' as a word it was not offered"),
                        excused
                    )
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

    /// Whether a reading is written out as whole words: `PaymentSheet` or "payment sheets" for "payment sheet", never "our time" inside "four times".
    static func isWritten(_ reading: String, in rewritten: String) -> Bool {
        let wanted = DoubtfulSpan.closedUp(reading)
        guard !wanted.isEmpty else { return false }
        let (written, begins, ends) = closedUpEdges(rewritten)
        // The rewrite may inflect the run it was given — "payment sheets" for "payment sheet" — and change it no further.
        let forms = inflections(of: wanted).union([wanted])
        return begins.contains { start in
            forms.contains { form in
                let end = start + form.count
                return end <= written.count && ends.contains(end)
                    && String(written[start..<end]) == form
            }
        }
    }

    /// A text closed up, with the places a word begins and ends, reading a camel hump as an edge like `spelledInto`.
    static func closedUpEdges(_ text: String) -> (written: [Character], begins: Set<Int>, ends: Set<Int>) {
        var written: [Character] = []
        var begins: Set<Int> = []
        var ends: Set<Int> = [0]
        var previous: Character?
        for character in text {
            guard character.isLetter || character.isNumber else {
                previous = character
                continue
            }
            // A word opens at the start, after anything that is not a letter, and at a capital.
            if (previous.map { !$0.isLetter } ?? true) || character.isUppercase {
                begins.insert(written.count)
                ends.insert(written.count)
            }
            if !character.isLetter { ends.insert(written.count) }  // A digit closes the word before it.
            written += DoubtfulSpan.closedUp(String(character))
            previous = character
        }
        ends.insert(written.count)
        return (written, begins, ends)
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

    /// A repair may change a word's form, never which content words are there, either way round, or the order they came in. See `Docs/cleanup.md`.
    static func grammarVerdict(
        kept: String, rewritten: String, allowing doubtful: [DoubtfulSpan] = [], echoed: String = ""
    ) -> GuardVerdict {
        let alignment = RewriteAlignment(kept: kept, rewritten: rewritten)
        return grammarVerdict(
            alignment, excusing: readingVerdict(doubtful, in: alignment).excused, echoed: echoed,
            allowing: doubtful)
    }

    /// The same check over an alignment already in hand, each word judged against what stands in its own place.
    static func grammarVerdict(
        _ alignment: RewriteAlignment, excusing excused: Set<Int>, echoed: String,
        allowing doubtful: [DoubtfulSpan]
    ) -> GuardVerdict {
        let keptTokens = alignment.kept
        let rewrittenTokens = alignment.rewritten
        let echoTokens = grammarTokens(echoed)
        // The echo the caret pass took back opened the model's answer, so its words count as survivors ahead of the rest.
        let written = (echoTokens + rewrittenTokens).filter(\.isPlain)
        // A number spoken over several words answers to the one numeral the rewrite wrote for it.
        let composed = composedNumbers(keptTokens, in: Set(written.map(\.matching)))
        let carried = keptTokens.indices.filter { index in
            let token = keptTokens[index]
            return token.isPlain && isContent(token) && !composed.contains(index) && !excused.contains(index)
        }
        if case .rejected(let reason) = survivalVerdict(carried.map { keptTokens[$0] }, in: written) {
            return .rejected(reason: reason)
        }
        if case .rejected(let reason) = placeVerdict(Set(carried), in: alignment, echo: echoTokens) {
            return .rejected(reason: reason)
        }
        let dropped = negators(in: keptTokens) - negators(in: rewrittenTokens + echoTokens)
        if dropped > 0 {
            return .rejected(reason: "the rewrite dropped a negation")
        }
        // The echo is the field's text before the caret, so it is an origin a negation may come from, never a total.
        let added = negators(in: rewrittenTokens) - negators(in: keptTokens) - negators(in: echoTokens)
        if added > 0 {
            return .rejected(reason: "the rewrite added a negation")
        }
        let churn = functionWordChurn(keptTokens, rewrittenTokens)
        if churn > 3 * sentenceCount(alignment.rewrittenText) {
            return .rejected(reason: "the rewrite changed \(churn) small words")
        }
        return inventionVerdict(
            kept: keptTokens, rewritten: rewrittenTokens, echo: echoTokens, allowing: doubtful)
    }

    /// Refuses a carried word that a changed run lost, judging it only against the words standing in that run's place.
    static func placeVerdict(
        _ carried: Set<Int>, in alignment: RewriteAlignment, echo: [GrammarToken]
    ) -> GuardVerdict {
        for change in alignment.changes {
            let here = (alignment.rewritten[change.rewritten] + echo).filter(\.isPlain)
            for index in change.kept where carried.contains(index) {
                let token = alignment.kept[index]
                guard !here.contains(where: { survives(token.matching, as: $0) }) else { continue }
                return .rejected(reason: "the rewrite lost or replaced '\(token.text)'")
            }
        }
        return .accepted
    }

    /// Refuses a content word the model brought in, an addition being the same fault as a loss read the other way.
    static func inventionVerdict(
        kept: [GrammarToken], rewritten: [GrammarToken], echo: [GrammarToken],
        allowing doubtful: [DoubtfulSpan]
    ) -> GuardVerdict {
        // A draft the checks cannot read romanises into words with no counterpart here, so the base checks keep it.
        guard kept.allSatisfy(\.isPlain) else { return .accepted }
        let origins = (kept + echo).filter(\.isPlain)
        // A reading offered for a doubtful word is by definition not what was said, and `candidateVerdict` judges it.
        let readings = Set(
            doubtful
                .flatMap { $0.candidates }
                .flatMap { $0.split(whereSeparator: \.isWhitespace) }
                .map { DoubtfulSpan.closedUp(String($0)) })
        for token in rewritten
        where token.isPlain && isContent(token) && !readings.contains(DoubtfulSpan.closedUp(token.text)) {
            if !origins.contains(where: { survives(token.matching, as: $0) })
                && !isSpelled(token.text, from: origins)
            {
                return .rejected(reason: "the rewrite invented '\(token.text)'")
            }
        }
        return .accepted
    }

    /// Whether an identifier is spelled wholly from said words, every part of it one of them and in the order they were said.
    static func isSpelled(_ identifier: String, from said: [GrammarToken]) -> Bool {
        let parts = identifierParts(identifier)
        guard parts.count > 1 else { return false }
        var next = said.startIndex
        for part in parts {
            guard let place = said[next...].firstIndex(where: { survives(part, as: $0) }) else {
                return false
            }
            next = place + 1
        }
        return true
    }

    /// The words an identifier is written from, cut at a camel hump and at anything not a letter or digit.
    static func identifierParts(_ identifier: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for character in identifier where character != "'" && character != "\u{2019}" {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { parts.append(current) }
                current = ""
                previous = nil
                continue
            }
            if character.isUppercase, previous.map({ $0.isLowercase || $0.isNumber }) == true {
                parts.append(current)
                current = ""
            }
            current += character.lowercased()
            previous = character
        }
        if !current.isEmpty { parts.append(current) }
        return parts
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
        return joiningOneWordSpellings(tokens)
    }

    /// Two words written apart for one word, keyed by the one word; a listed pair, never a rule about shape.
    static let oneWordSpellings: [String: (first: String, second: String)] = [
        "cannot": ("can", "not")
    ]

    /// Reads a listed pair written apart as its one word, so "can not" and "cannot" are the same word either way round.
    static func joiningOneWordSpellings(_ tokens: [GrammarToken]) -> [GrammarToken] {
        var joined: [GrammarToken] = []
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            let next = index + 1 < tokens.endIndex ? tokens[index + 1] : nil
            if let next, !next.startsSentence,
                let word = oneWordSpellings.first(where: {
                    $0.value.first == token.matching && $0.value.second == next.matching
                })?.key
            {
                joined.append(
                    GrammarToken(
                        text: token.text + next.text, lookup: word, matching: word,
                        startsSentence: token.startsSentence))
                index += 2
                continue
            }
            joined.append(token)
            index += 1
        }
        return joined
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

    /// Whether one rewritten word is the kept word: exact, as its numeral or its word, in an inflected form, in an identifier, or as a verb form.
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

    /// The words that reverse a sentence, apostrophes aside; dropping or adding one is the worst edit the model can make.
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

    /// The first number the rewrite states that the speaker did not state, there and that many times, or nil.
    static func inventedNumber(original: String, rewritten: String) -> String? {
        // Read in words on the written side too, so "twenty chairs" is refused where "20 chairs" already was.
        var spoken = numberSequence(in: original, reading: numberWords)[...]
        for number in numberSequence(in: rewritten, reading: englishNumberWords) {
            guard let found = spoken.firstIndex(of: number) else { return number }
            spoken = spoken[(found + 1)...]
        }
        return nil
    }

    /// The numbers a text states, in order and with repeats kept, each number word read through `table` and every run of them composed after it.
    static func numberSequence(in text: String, reading table: [String: String]) -> [String] {
        var pieces: [(text: String, isDigits: Bool)] = []
        var run = ""
        var runIsDigits = false
        func flush() {
            if !run.isEmpty { pieces.append((run, runIsDigits)) }
            run = ""
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
        // A run of digits stands between number words, so it ends a spoken number rather than joining it.
        let words = pieces.map { $0.isDigits ? "" : $0.text.lowercased() }
        var found: [String] = []
        var index = words.startIndex
        while index < words.endIndex {
            if pieces[index].isDigits {
                found.append(pieces[index].text)
                index += 1
            } else if let read = NumberWords.cardinal(words[index...]), read.count > 1 {
                found += words[index..<(index + read.count)].compactMap { table[$0] }
                found.append(String(read.value))
                index += read.count
            } else {
                if let digits = table[words[index]] { found.append(digits) }
                index += 1
            }
        }
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

    /// The positions of every spoken number run the rewrite wrote as the one numeral it comes to.
    static func composedNumbers(_ tokens: [GrammarToken], in pool: Set<String>) -> Set<Int> {
        var covered: Set<Int> = []
        for run in cardinalRuns(tokens.map(\.matching)) where pool.contains(String(run.value)) {
            covered.formUnion(run.start..<(run.start + run.count))
        }
        return covered
    }

    /// Every run of two or more words that `NumberWords` reads as one cardinal, longest first from each start.
    private static func cardinalRuns(_ words: [String]) -> [(start: Int, count: Int, value: Int)] {
        var runs: [(start: Int, count: Int, value: Int)] = []
        var index = words.startIndex
        while index < words.endIndex {
            guard let read = NumberWords.cardinal(words[index...]), read.count > 1 else {
                index += 1
                continue
            }
            runs.append((index, read.count, read.value))
            index += read.count
        }
        return runs
    }
}
