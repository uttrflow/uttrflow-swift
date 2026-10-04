import Foundation
public import UttrflowCore

/// Capitalises each sentence and the pronoun "I", then cases the first word the way the formatter and the caret say.
public struct FirstWordPass: WholeTextCleaningPass {
    public static let id: PassID = .firstWord

    public let policy: FirstWordPolicy
    public let state: InsertionPoint.SentenceState
    /// Where a name can be sighted besides the text itself: the title, the selection, the text at the caret.
    public let onScreen: [String]
    /// The transcript whose case `.asSpoken` copies; nil reads it off the draft's own heard words.
    public let heard: String?
    /// Whether calendar and known proper names use their standard casing.
    public let capitaliseCalendarWords: Bool

    public init(
        policy: FirstWordPolicy = .fromInsertionPoint, state: InsertionPoint.SentenceState = .unknown,
        onScreen: [String] = [], heard: String? = nil, capitaliseCalendarWords: Bool = true
    ) {
        self.policy = policy
        self.state = state
        self.onScreen = onScreen
        self.heard = heard
        self.capitaliseCalendarWords = capitaliseCalendarWords
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let text = draft.text
        let heardWords =
            heard.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            ?? draft.words.map(\.heard).filter { !$0.isEmpty }
        var startOfSentence = true
        var isFirst = true
        let present = draft.presentIndices
        for (order, index) in present.enumerated() {
            let word = draft.words[index]
            guard !word.isLayoutMark else {
                // Every layout mark starts a new sentence.
                startOfSentence = true
                continue
            }
            let letterAdjacent = Self.hasLetterNameBesideI(at: order, in: present, of: draft)
            if letterAdjacent, WordShape(word.text).key == "i" {
                let cased = WordShape(word.text).replacingCore(with: "i")
                draft.replace(at: index, with: cased, by: Self.id)
                startOfSentence = Self.endsSentence(cased) && !WordShape.trailsOff(WordShape(cased).suffix)
                isFirst = false
                continue
            }
            var cased = Self.pronounCapitalised(word.text)
            if isFirst {
                // The case is read from where this word stands, so a word a pass dropped cannot decide it.
                let spokenBefore = draft.words[..<index].filter { !$0.heard.isEmpty }.count
                cased = firstWord(
                    undoingOpeningContraction(cased, heard: word.heard),
                    in: text, heard: Array(heardWords.dropFirst(spokenBefore)))
            } else if startOfSentence {
                cased = WordShape.capitalised(cased)
            } else if capitaliseCalendarWords {
                cased = Self.properNameCapitalised(
                    Self.calendarWordCapitalised(cased), in: text)
            }
            draft.replace(at: index, with: cased, by: Self.id)
            // A word trailing off in an ellipsis is a pause, so the next keeps the case it was heard in.
            let next = present.dropFirst(order + 1).first.map { draft.words[$0].text }
            startOfSentence =
                Self.endsSentence(cased, followedBy: next) && !WordShape.trailsOff(WordShape(cased).suffix)
            isFirst = false
        }
        return draft
    }

    /// The first word under the policy: a capital, the case it was heard in, or lower-case after a mid-sentence caret.
    private func firstWord(_ word: String, in text: String, heard: [String]) -> String {
        switch policy {
        case .alwaysCapital:
            return WordShape.capitalised(word)
        case .asSpoken:
            return Self.matchingHeardCase(word, heard: heard)
        case .fromInsertionPoint:
            guard state == .midSentence, !Self.keepsCapital(word),
                !(capitaliseCalendarWords && Self.isCalendarWord(word)),
                !Self.isProperName(word, in: text),
                !Self.looksLikeName(word, in: [text] + onScreen)
            else { return WordShape.capitalised(word) }
            return WordShape.lowercased(word)
        }
    }

    /// The heard "id" or "ill" back in place of "I'd" or "I'll" mid-sentence, where its capital only opened the piece.
    func undoingOpeningContraction(_ word: String, heard: String) -> String {
        guard policy == .fromInsertionPoint, state == .midSentence else { return word }
        let heardShape = WordShape(heard)
        guard let contraction = ContractionsPass.capitalisedOnly[heardShape.key],
            WordShape(word).core == contraction
        else { return word }
        return WordShape(word).replacingCore(with: heardShape.core)
    }

    /// Whether the word closes a sentence; a dotted abbreviation such as "p.m." carries a stop of its own.
    static func endsSentence(_ text: String) -> Bool {
        let shape = WordShape(text)
        guard shape.endsSentence else { return false }
        guard let abbreviation = dottedAbbreviation(atSentenceEnd: shape) else { return true }
        return !isAbbreviation(abbreviation)
    }

    static func endsSentence(_ text: String, followedBy next: String?) -> Bool {
        let shape = WordShape(text)
        guard shape.endsSentence else { return false }
        guard let abbreviation = dottedAbbreviation(atSentenceEnd: shape), isAbbreviation(abbreviation) else {
            return true
        }
        guard let next, let first = next.first else { return false }
        if isTitle(abbreviation) { return false }
        return first.isUppercase
    }

    /// The abbreviation whose full stop is the last sentence mark, if any.
    private static func dottedAbbreviation(atSentenceEnd shape: WordShape) -> String? {
        guard shape.suffix.reversed().first(where: { ".!?…।॥".contains($0) }) == "." else { return nil }
        return shape.core.lowercased()
    }

    private static func isTitle(_ word: String) -> Bool {
        ["mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof"].contains(word)
    }

    private static func isAbbreviation(_ word: String) -> Bool {
        InsertionPoint.sentenceAbbreviations.contains(word) || word.contains(".") || word.count == 1
            || ["mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "approx", "dept", "fig", "eg", "ie"]
                .contains(word)
    }

    /// "i" and "i'll" become "I" and "I'll"; nothing else changes.
    static func pronounCapitalised(_ text: String) -> String {
        let shape = WordShape(text)
        guard shape.key == "i" || shape.key.hasPrefix("i'") || shape.key.hasPrefix("i\u{2019}") else {
            return text
        }
        return shape.replacingCore(with: "I" + shape.core.dropFirst())
    }

    private static func hasLetterNameBesideI(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        let index = live[position]
        guard WordShape(draft.words[index].text).key == "i" else {
            return false
        }
        let names = SpelledInitialismPass.letterNamesForCasing
        let previousIsLetter =
            position > 0
            && live[position - 1] + 1 == index
            && !draft.shape(at: live[position - 1]).endsClause
            && names.contains(draft.shape(at: live[position - 1]).key)
        let nextIsLetter =
            position + 1 < live.count
            && live[position + 1] == index + 1
            && !draft.shape(at: index).endsClause
            && names.contains(draft.shape(at: live[position + 1]).key)
        return previousIsLetter || nextIsLetter
    }

    /// Gives unambiguous weekday and month names their conventional case without guessing at May or March.
    static func calendarWordCapitalised(_ text: String) -> String {
        let shape = WordShape(text)
        guard isCalendarWord(text) else { return text }
        return shape.replacingCore(with: WordShape.capitalised(shape.core))
    }

    /// Gives unambiguous English language, country, city, state and nationality names their conventional case.
    static func properNameCapitalised(_ text: String, in context: String) -> String {
        let shape = WordShape(text)
        guard isProperName(text, in: context) else { return text }
        return shape.replacingCore(with: WordShape.capitalised(shape.core))
    }

    static func isProperName(_ text: String, in context: String) -> Bool {
        let key = WordShape(text).key.lowercased()
        return properNames.contains(key) || isNewYorkWord(key, in: context)
    }

    /// Recognises each half of the fixed city name without capitalising ordinary uses of "new" or "york".
    private static func isNewYorkWord(_ key: String, in context: String) -> Bool {
        guard key == "new" || key == "york" else { return false }
        let words = context.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return zip(words, words.dropFirst()).contains { $0 == "new" && $1 == "york" }
    }

    private static let properNames: Set<String> = {
        let english = Locale(identifier: "en")
        let languages = Locale.LanguageCode.isoLanguageCodes.compactMap {
            english.localizedString(forIdentifier: $0.identifier)
        }
        let regions = Locale.Region.isoRegions.compactMap {
            english.localizedString(forRegionCode: $0.identifier)
        }
        let systemNames = (languages + regions).flatMap { name in
            let words = name.split(whereSeparator: { !$0.isLetter })
            return words.count == 1 ? [String(words[0]).lowercased()] : []
        }
        return Set(
            systemNames + [
                "london", "tokyo", "paris", "texas", "german", "germans", "indian", "indians",
            ]
        ).subtracting(namesThatAreOrdinaryWords)
    }()

    /// Locale names that are also everyday English words, so they carry no capital without a cue.
    private static let namesThatAreOrdinaryWords: Set<String> = [
        "afar", "chad", "china", "ewe", "fang", "guernsey", "guinea", "jersey", "polish", "slave",
        "turkey", "world",
    ]

    /// Whether a word names a weekday or an unambiguous month.
    static func isCalendarWord(_ text: String) -> Bool {
        calendarWords.contains(WordShape(text).key.lowercased())
    }

    private static let calendarWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "april", "june", "july", "august", "september", "october", "november",
        "december",
    ]

    /// Whether a word keeps its capital mid-sentence: "I" and its contractions, an acronym, or a letter-and-digit code.
    static func keepsCapital(_ word: String) -> Bool {
        let core = WordShape(word).core
        if core == "I" || core.hasPrefix("I'") || core.hasPrefix("I\u{2019}") { return true }
        let letters = core.filter(\.isLetter)
        if core.contains(where: \.isNumber) && letters.contains(where: \.isUppercase) { return true }
        return (letters.count >= 2 && letters.allSatisfy(\.isUppercase)) || WordShape.hasInternalCapital(core)
    }

    /// Copies the case the word was heard in from where it stands, skipping fillers; a changed word is left alone.
    static func matchingHeardCase(_ word: String, heard: [String]) -> String {
        let letters = WordShape(word).core.filter(\.isLetter).lowercased()
        guard !letters.isEmpty,
            let spoken = heard.first(where: { $0.filter(\.isLetter).lowercased() == letters })
        else { return word }
        return WordShape(word).replacingCore(with: WordShape(spoken).core)
    }

    /// Whether a text holds the word capitalised off a sentence start; a title-cased text says nothing.
    static func looksLikeName(_ word: String, in texts: [String]) -> Bool {
        let wanted = bareWord(word[...]).lowercased()
        guard !wanted.isEmpty else { return false }
        return texts.contains { text in
            let lines = text.split(whereSeparator: \.isNewline)
                .map { $0.split(whereSeparator: \.isWhitespace) }
            guard lines.joined().contains(where: { bareWord($0).first?.isLowercase ?? false }) else {
                return false
            }
            return lines.contains { line in
                zip(line, line.dropFirst()).contains { previous, token in
                    let candidate = bareWord(token)
                    let startsSentence = previous.last.map(SentenceMarks.ends.contains) ?? false
                    return (candidate.first?.isUppercase ?? false) && candidate.lowercased() == wanted
                        && !startsSentence
                }
            }
        }
    }

    /// Lowercases an ordinary run-on sentence opening without changing names, acronyms, or calendar words.
    public static func lowercasedAtRunOnSeam(_ word: String, in context: String) -> String? {
        guard !keepsCapital(word), !isCalendarWord(word), !looksLikeName(word, in: [context]) else {
            return nil
        }
        return WordShape.lowercased(word)
    }

    /// The token without the quotes, brackets and marks around it.
    private static func bareWord(_ token: Substring) -> Substring {
        guard let start = token.firstIndex(where: { $0.isLetter || $0.isNumber }),
            let end = token.lastIndex(where: { $0.isLetter || $0.isNumber })
        else { return "" }
        return token[start...end]
    }
}
