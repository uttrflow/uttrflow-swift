import Foundation
public import UttrflowCore

/// Capitalises each sentence and the pronoun "I", then cases the first word the way the formatter and the caret say.
public struct FirstWordPass: WholeTextCleaningPass {
    public static let id: PassID = .firstWord
    public static let laws: Set<PassLaw> = [.addsNoWords, .idempotent, .keepsDigits, .latinOnly]

    public let policy: FirstWordPolicy
    public let state: InsertionPoint.SentenceState
    /// Where a name can be sighted besides the text itself: the title, the selection, the text at the caret.
    public let onScreen: [String]
    /// The transcript whose case `.asSpoken` copies; nil reads it off the draft's own heard words.
    public let heard: String?
    /// Whether calendar and known proper names use their standard casing, and stray mid-sentence capitals are lowered.
    public let capitaliseCalendarWords: Bool
    /// Each word of the user's dictionary entries for this dictation, lower-cased; a capital on one of them is kept.
    public let ownWords: Set<String>
    /// Known spellings that start with a lower-case letter, keyed in lower case; a sentence start keeps that spelling.
    public let pinnedSpellings: [String: String]
    /// Whether a line opening with a program typed at a prompt keeps the case it was heard in, as source does.
    public let keepsCommandCase: Bool
    /// Every term the lexicon, the screen or the user's dictionary writes its own way, keyed in lower case.
    let namedForms: [String: String]

    public init(
        policy: FirstWordPolicy = .fromInsertionPoint, state: InsertionPoint.SentenceState = .unknown,
        onScreen: [String] = [], heard: String? = nil, capitaliseCalendarWords: Bool = true,
        vocabulary: [String] = [], casing: AcronymCasingPass? = nil, keepsCommandCase: Bool = false
    ) {
        self.keepsCommandCase = keepsCommandCase
        self.policy = policy
        self.state = state
        self.onScreen = onScreen
        self.heard = heard
        self.capitaliseCalendarWords = capitaliseCalendarWords
        self.ownWords = Set(
            vocabulary.flatMap { $0.split(whereSeparator: \.isWhitespace) }.map {
                WordShape(String($0)).core.lowercased()
            })
        let casing = casing ?? AcronymCasingPass(vocabulary: vocabulary)
        self.pinnedSpellings = casing.lowerCaseForms
        self.namedForms = casing.forms
    }

    /// The word in the user's own spelling when that spelling starts lower case; otherwise unchanged.
    func keepingPinnedCase(_ word: String) -> String {
        let shape = WordShape(word)
        guard let spelling = pinnedSpellings[shape.core.lowercased()] else { return word }
        return shape.replacingCore(with: spelling)
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = policy == .fromInsertionPoint ? unshouted(draft) : draft
        let text = draft.text
        let heardWords =
            heard.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            ?? draft.words.map(\.heard).filter { !$0.isEmpty }
        var startOfSentence = true
        var isFirst = true
        var afterPause = false
        let present = draft.presentIndices
        let datedMonths = NumberFormsPass.datedMonths(in: present.map { draft.shape(at: $0) })
        for (order, index) in present.enumerated() {
            let word = draft.words[index]
            guard !word.isLayoutMark else {
                // Every layout mark starts a new sentence.
                startOfSentence = true
                continue
            }
            if WordShape(word.text).isOption {
                // An option's letters are what the shell reads, so no casing rule touches them.
                startOfSentence = false
                afterPause = false
                isFirst = false
                continue
            }
            let letterAdjacent = Self.hasLetterNameBesideI(at: order, in: present, of: draft)
            if letterAdjacent, !isFirst, !startOfSentence, WordShape(word.text).key == "i" {
                let cased = WordShape(word.text).replacingCore(with: "i")
                draft.replace(at: index, with: cased, by: Self.id)
                let following = present.dropFirst(order + 1).first.map { draft.words[$0].text }
                startOfSentence =
                    Abbreviations.endsSentence(cased, followedBy: following)
                    && !WordShape.trailsOff(WordShape(cased).suffix)
                afterPause = WordShape.trailsOff(WordShape(cased).suffix)
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
                cased = keepingPinnedCase(cased)
            } else if startOfSentence {
                cased = keepingPinnedCase(WordShape.capitalised(cased))
            } else if policy == .fromInsertionPoint,
                Self.followsDemotedSentenceEnd(at: order, in: present, of: draft),
                FunctionWords.holds(WordShape(cased).key),
                !Self.keepsCapital(cased),
                !(capitaliseCalendarWords && Self.isCalendarWord(cased)),
                !Self.isProperName(cased, in: text),
                !Self.looksLikeName(cased, in: [Self.otherText(excluding: index, in: draft)] + onScreen)
            {
                cased = WordShape.lowercased(cased)
            } else if capitaliseCalendarWords, datedMonths.contains(order) {
                cased = WordShape(cased).replacingCore(with: WordShape.capitalised(WordShape(cased).core))
            } else if capitaliseCalendarWords {
                let unstrayed = afterPause ? cased : strayCapitalLowered(cased, in: text)
                cased = Self.properNameCapitalised(
                    Self.titleCapitalised(Self.calendarWordCapitalised(unstrayed)), in: text)
                cased = Self.kinshipCased(cased, at: order, in: present, of: draft)
            }
            draft.replace(at: index, with: cased, by: Self.id)
            // A word trailing off in an ellipsis is a pause, so the next keeps the case it was heard in.
            let next = present.dropFirst(order + 1).first.map { draft.words[$0].text }
            startOfSentence =
                Abbreviations.endsSentence(cased, followedBy: next)
                && !WordShape.trailsOff(WordShape(cased).suffix)
            afterPause = WordShape.trailsOff(WordShape(cased).suffix)
            isFirst = false
        }
        return draft
    }

    /// Lowers every unedited word of a transcript the decoder returns all in capitals; a known term keeps its form.
    func unshouted(_ draft: Draft) -> Draft {
        let spoken = draft.presentIndices.filter { !draft.words[$0].heard.isEmpty }
        let lettered = spoken.map { WordShape(draft.words[$0].heard).core.filter(\.isLetter) }.filter {
            $0.count >= 2
        }
        guard lettered.count >= Self.minimumShoutedWords,
            lettered.allSatisfy({ $0.allSatisfy(\.isUppercase) })
        else { return draft }
        var draft = draft
        for index in spoken where draft.words[index].text == draft.words[index].heard {
            let shape = WordShape(draft.words[index].text)
            let key = shape.core.lowercased()
            let lowered = shape.replacingCore(with: namedForms[key] ?? key)
            if lowered != draft.words[index].text { draft.replace(at: index, with: lowered, by: Self.id) }
        }
        return draft
    }

    /// Words of two letters or more a transcript needs, all in capitals, before its capitals are read as the decoder's.
    static let minimumShoutedWords = 3

    private static func followsDemotedSentenceEnd(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard position > 0 else { return false }
        let index = live[position]
        let previous = live[position - 1]
        let replacedWithComma = draft.words[previous].edits.contains { edit in
            edit.by == SpokenPunctuationPass.id && edit.kind == .replaced
                && WordShape(edit.to).suffix.hasSuffix(",")
        }
        guard replacedWithComma else { return false }
        return ((previous + 1)..<index).contains { removed in
            guard case .removed(by: SpokenPunctuationPass.id) = draft.words[removed].state else {
                return false
            }
            return WordShape(draft.words[removed].heard).endsSentence
        }
    }

    private static func otherText(excluding index: Int, in draft: Draft) -> String {
        draft.presentIndices.filter { $0 != index }.map { draft.words[$0].text }.joined(separator: " ")
    }

    /// The first word under the policy: a capital, the case it was heard in, or lower-case after a mid-sentence caret.
    private func firstWord(_ word: String, in text: String, heard: [String]) -> String {
        if keepsCommandCase, TechnicalLexicon.opensCommandLine(heard) {
            return Self.matchingHeardCase(word, heard: heard)
        }
        switch policy {
        case .alwaysCapital:
            return WordShape.capitalised(word)
        case .asSpoken:
            return Self.matchingHeardCase(word, heard: heard)
        case .fromInsertionPoint:
            guard state == .midSentence, !Self.keepsCapital(word),
                !(capitaliseCalendarWords && Self.isCalendarWord(word)),
                !(capitaliseCalendarWords && Self.isMonthOpeningAPiece(word)),
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
        let previousIsLetter =
            position > 0
            && live[position - 1] + 1 == index
            && !draft.shape(at: live[position - 1]).endsClause
            && LetterRun.isLetterName(draft.shape(at: live[position - 1]).key)
        let nextIsLetter =
            position + 1 < live.count
            && live[position + 1] == index + 1
            && !draft.shape(at: index).endsClause
            && LetterRun.isLetterName(draft.shape(at: live[position + 1]).key)
        return previousIsLetter || nextIsLetter
    }

    /// Gives unambiguous weekday and month names their conventional case without guessing at May or March.
    static func calendarWordCapitalised(_ text: String) -> String {
        let shape = WordShape(text)
        guard isCalendarWord(text) else { return text }
        return shape.replacingCore(with: WordShape.capitalised(shape.core))
    }

    /// A title written with its own stop before a name, as "dr." in "see dr. lee", takes its capital.
    static func titleCapitalised(_ text: String) -> String {
        let shape = WordShape(text)
        guard shape.suffix.hasPrefix("."), Abbreviations.kind(of: shape.core) == .title,
            Abbreviations.ownsStop(shape.core)
        else { return text }
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

    /// A kinship word as a name ("tell Mom") unless an article or possessive up to one word before it makes it a common noun.
    static func kinshipCased(_ word: String, at position: Int, in live: [Int], of draft: Draft) -> String {
        let shape = WordShape(word)
        guard KinshipWords.holds(shape.core), !keepsCapital(word) else { return word }
        let before = live[..<position].suffix(2).reversed().map { draft.shape(at: $0) }
        let unbroken = before.prefix { !$0.endsClause }
        let commonNoun = unbroken.contains { KinshipWords.marksCommonNoun($0.core) }
        let core = commonNoun ? shape.core.lowercased() : WordShape.capitalised(shape.core.lowercased())
        return shape.replacingCore(with: core)
    }

    /// Whether a word names a weekday or an unambiguous month.
    static func isCalendarWord(_ text: String) -> Bool {
        calendarWords.contains(WordShape(text).key.lowercased())
    }

    /// Whether a piece opens on "March" the recogniser capitalised: the month, since the verb rarely opens one, while "May" stays a modal.
    static func isMonthOpeningAPiece(_ word: String) -> Bool {
        let core = WordShape(word).core
        return core.first?.isUppercase == true && core.lowercased() == "march"
    }

    private static let calendarWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "april", "june", "july", "august", "september", "october", "november",
        "december",
    ]

    /// An ordinary word the recogniser capitalised mid-sentence, lowered unless the dictionary or the screen holds it capitalised.
    func strayCapitalLowered(_ word: String, in text: String) -> String {
        let core = WordShape(word).core
        guard policy == .fromInsertionPoint, core.first?.isUppercase == true, !Self.keepsCapital(word),
            LexicalClass.isKnownEnglishWord(core.lowercased()),
            !LexicalClass.isNameInDictionary(core.lowercased()),
            !ownWords.contains(core.lowercased()),
            namedForms[core.lowercased()] == nil, !LexicalClass.isNamed(core, in: text),
            !Self.isCalendarWord(word), !Self.isProperName(word, in: text),
            !Self.looksLikeName(word, in: onScreen)
        else { return word }
        return WordShape.lowercased(word)
    }

    /// Whether a word keeps its case mid-sentence: "I" and its contractions, an acronym, or a technical token.
    static func keepsCapital(_ word: String) -> Bool {
        let core = WordShape(word).core
        // A mention or an address is written as its owner spells it.
        if word.contains("@") { return true }
        if core == "I" || core.hasPrefix("I'") || core.hasPrefix("I\u{2019}") { return true }
        let letters = core.filter(\.isLetter)
        if core.contains(where: \.isNumber) && letters.contains(where: \.isUppercase) { return true }
        return (letters.count >= 2 && letters.allSatisfy(\.isUppercase)) || WordShape.keepsWrittenCase(core)
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
