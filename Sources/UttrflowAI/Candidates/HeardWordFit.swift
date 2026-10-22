// When a heard word cannot stand in its place, which is the only time a sound-alike nobody wrote down is offered.
import UttrflowCore
import UttrflowDictionary

/// The rules under which a doubtful run's heard words cannot stand in their slot. See Docs/cleanup.md.
enum HeardWordFit {
    /// Why a heard run cannot stand in its place.
    enum Rule: Equatable {
        /// A word of the run is no word the lexicon or the vocabulary knows, in a sentence with no romanised Hindi.
        case notAWord
        /// A possessive determiner closes its sentence, with no noun after it ("put it over their").
        case possessiveClosing
        /// A possessive determiner follows an article ("wait an our").
        case possessiveAfterArticle
        /// A possessive determiner stands before a form of "be" ("their is a problem").
        case possessiveBeforeBe
        /// "too" stands before a pronoun that is only ever an object ("send it too me").
        case tooBeforeObject
    }

    /// The articles, after which a second determiner cannot stand.
    static let articles: Set<String> = ["a", "an", "the"]

    /// The rule that rules the run at `range` of the said words out, or `nil` when the words can stand as heard.
    static func ruledOut(_ range: Range<Int>, in said: [String]) -> Rule? {
        guard !range.isEmpty, range.upperBound <= said.count else { return nil }
        if range.contains(where: { isUnknown(said[$0]) }),
            !WordCorrectionEngine.speaksHindi(Array(said[sentence(around: range, in: said)]))
        {
            return .notAWord
        }
        guard range.count == 1 else { return nil }
        let index = range.lowerBound
        let shape = WordShape(said[index])
        let before =
            index > 0 && !WordShape(said[index - 1]).endsSentence ? WordShape(said[index - 1]).key : nil
        let after = index + 1 < said.count && !shape.endsSentence ? WordShape(said[index + 1]).key : nil
        if FunctionWords.possessives.contains(shape.key) {
            if after == nil { return .possessiveClosing }
            if let before, articles.contains(before) { return .possessiveAfterArticle }
            if let after, FunctionWords.beForms.contains(after) { return .possessiveBeforeBe }
        }
        if shape.key == "too", let after, FunctionWords.objectOnlyPronouns.contains(after) {
            return .tooBeforeObject
        }
        return nil
    }

    /// The said words of the sentence that holds the run, between the stops on either side of it.
    static func sentence(around range: Range<Int>, in said: [String]) -> Range<Int> {
        let start = said[..<range.lowerBound].lastIndex { WordShape($0).endsSentence }.map { $0 + 1 } ?? 0
        let end =
            said[(range.upperBound - 1)...].firstIndex { WordShape($0).endsSentence }.map { $0 + 1 } ?? said.count
        return start..<end
    }

    /// Whether the run holds a name, which no sound-alike re-spells unless the user's dictionary holds it ("John", never "Jon").
    static func isName(_ range: Range<Int>, in said: [String]) -> Bool {
        range.contains { index in
            let core = WordShape(said[index]).core
            guard core.first?.isUppercase == true, core != "I" else { return false }
            return LexicalClass.isNameInDictionary(core)
                || LexicalClass.isNamed(core, in: said.joined(separator: " "))
        }
    }

    /// Whether the word has letters and neither the pronunciation lexicon nor the general vocabulary holds it.
    static func isUnknown(_ text: String) -> Bool {
        let key = WordShape(text).key
        guard key.contains(where: \.isLetter) else { return false }
        return !PhonemeLexicon.shared.holds(key) && !GeneralVocabulary.isOrdinary(key)
    }
}

extension WordShape {
    /// Whether the word closes a sentence with a stop, a question mark or an exclamation mark.
    fileprivate var endsSentence: Bool { suffix.contains(where: { ".!?".contains($0) }) }
}
