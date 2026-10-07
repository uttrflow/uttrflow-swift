public import UttrflowCore
import UttrflowDictionary

/// Writes an acronym, tool, language or file name in its known casing from the lexicon, dictionary and screen.
public struct AcronymCasingPass: WholeTextCleaningPass {
    public static let id: PassID = .acronymCasing
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// Each known written form, keyed by its lower-cased letters; an ordinary word is a key only as the screen writes it.
    public let forms: [String: String]
    /// Each known file name or file-name stem, keyed by its lower-cased form: AGENTS.md, README.
    let fileForms: [String: String]
    /// Screen keys that are ordinary or English words, cased only where the screen writes them beside a spoken neighbour.
    let sightedEnglishKeys: Set<String>
    /// The screen's words, checked for that neighbour.
    let screen: ScreenWords

    public init(destination: Destination = .plain, vocabulary: [String] = [], onScreen: [String] = []) {
        let terms = TechnicalLexicon.terms
            .filter { Self.namedCategories.contains($0.category) && $0.applies(in: destination) }
        let lexicon = terms.map(\.id)
        // A spelt-out acronym such as HTTPS claims no ordinary word, so its form is a key even when it spells one.
        let vouched = terms.filter { !$0.claimsOrdinaryWrittenForm(GeneralVocabulary.isOrdinary) }
        let lexiconKeys = Set(vouched.map { $0.id.lowercased() })
        let own = vocabulary.filter { !$0.contains(where: \.isWhitespace) }.map { WordShape($0).core }
        let sighted = onScreen.flatMap { WordTokens.words($0, .display) }.map { WordShape($0).core }
        var forms: [String: String] = [:]
        var sightedEnglish: Set<String> = []
        // Later sources win: the user's spelling beats the screen's, and the screen's beats the lexicon's.
        let sources = [
            (lexicon.filter { lexiconKeys.contains($0.lowercased()) && Self.isOneWord($0) }, true),
            (sighted.filter(Self.isAcronym), true), (own.filter(Self.isOneWord), false),
        ]
        for (source, vetted) in sources {
            // An ordinary word the lexicon does not vouch for is cased only from the screen, beside its neighbour.
            for form in source where vetted || !GeneralVocabulary.isOrdinary(form) {
                forms[form.lowercased()] = form
            }
        }
        for form in sighted.filter(Self.isAcronym) where forms[form.lowercased()] == form {
            let key = form.lowercased()
            let named = lexicon.contains { $0.lowercased() == key } || own.contains { $0.lowercased() == key }
            let unvouched = GeneralVocabulary.isOrdinary(key) && !lexiconKeys.contains(key)
            if unvouched || (!named && LexicalClass.isKnownEnglishWord(key)) { sightedEnglish.insert(key) }
        }
        self.forms = forms
        self.sightedEnglishKeys = sightedEnglish
        self.screen = ScreenWords(texts: onScreen)
        let stems = TechnicalLexicon.terms
            .filter { $0.category == .fileFormat && $0.applies(in: destination) }.map(\.id).filter(
                Self.isOneWord)
        var fileForms: [String: String] = [:]
        for form in stems + sighted.filter(Self.isFileName) + own.filter(Self.isFileName) {
            fileForms[form.lowercased()] = form
        }
        self.fileForms = fileForms
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        for index in draft.presentIndices where !draft.words[index].isLayoutMark {
            let shape = draft.shape(at: index)
            guard let form = cased(shape.core), form != shape.core else { continue }
            let key = shape.core.lowercased()
            if sightedEnglishKeys.contains(key) || sightedEnglishKeys.contains(String(key.dropLast())),
                !screen.shows(form, besideAnyOf: neighbours(of: index, in: draft))
            {
                continue
            }
            draft.replace(at: index, with: shape.replacingCore(with: form), by: Self.id)
        }
        return draft
    }

    /// The written form of a word in lower case or as said at a sentence start, plural "apis" included.
    func cased(_ core: String) -> String? {
        guard core.dropFirst().allSatisfy({ !$0.isUppercase }) else { return nil }
        if Self.isFileName(core) { return casedFileName(core) }
        let key = core.lowercased()
        if let form = forms[key] { return form }
        guard key.hasSuffix("s"), let form = forms[String(key.dropLast())], form.last?.isUppercase == true
        else { return nil }
        return form + "s"
    }

    /// The lower-cased words written just before and just after one word.
    private func neighbours(of index: Int, in draft: Draft) -> [String] {
        let present = draft.presentIndices.filter { !draft.words[$0].isLayoutMark }
        guard let position = present.firstIndex(of: index) else { return [] }
        return [position - 1, position + 1].filter(present.indices.contains)
            .flatMap { WordShape.words(draft.words[present[$0]].text) }
    }

    /// A file name as seen whole, else its stem's known casing with the ending kept as spoken: "readme.md" is README.md.
    private func casedFileName(_ core: String) -> String? {
        if let form = fileForms[core.lowercased()] { return form }
        guard let dot = core.lastIndex(of: "."), !core[..<dot].contains(".") else { return nil }
        let stem = core[..<dot].lowercased()
        guard let form = fileForms[stem] else { return nil }
        return form + core[dot...]
    }

    /// Whether a written word is a file name: a name, a dot and a known ending.
    private static func isFileName(_ word: String) -> Bool {
        TechnicalToken.classify(word) == .fileName
    }

    /// The lexicon categories whose written form is a name with its own casing.
    private static let namedCategories: Set<TechnicalTerm.Category> = [.acronym, .tool, .language]

    /// The forms whose first letter is lower case, kept as written at a sentence start.
    var lowerCaseForms: [String: String] {
        forms.filter { $0.value.first(where: \.isLetter)?.isLowercase == true }
    }

    /// Whether a written form is one word of letters and digits, which a single spoken word can match.
    private static func isOneWord(_ form: String) -> Bool {
        !form.isEmpty && form.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Whether a written word holds a capital past its first letter; a name does not.
    private static func isAcronym(_ word: String) -> Bool {
        word.count >= 2 && word.allSatisfy { $0.isLetter || $0.isNumber }
            && WordShape.hasInternalCapital(word)
    }
}
