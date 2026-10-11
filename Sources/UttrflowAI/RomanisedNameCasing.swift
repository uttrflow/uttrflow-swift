// Capitals for romanised Hindi names, places and weekdays, from the person's dictionary, the names on the screen and the weekday table. See `Docs/latin-output.md`.
import UttrflowCore
import UttrflowDictionary

/// Writes a romanised Hindi word with its capital when a dictionary word, a name on the screen or the weekday table spells it, since Devanagari has no case; a respelled dictionary word is cased by `LoanwordRestoration`.
struct RomanisedNameCasing: Sendable {
    /// Each known written form, keyed by the romanised word's sound key.
    let forms: [String: String]

    /// The dictionary's names come first, then the names the screen shows, then the weekdays; an earlier source keeps its spelling.
    init(personal: [String] = [], onScreenNames: [String] = []) {
        var forms: [String: String] = [:]
        func add(_ written: String) {
            let key = Romaniser.soundKey(written)
            guard !key.isEmpty, !Self.tailWords.contains(key), forms[key] == nil else { return }
            forms[key] = written
        }
        Self.names(personal + onScreenNames).forEach(add)
        Self.weekdays.forEach(add)
        self.forms = forms
    }

    /// The draft with each word that came from Devanagari and names a known name, place or weekday written with its capital; every other word is untouched.
    func casing(_ draft: Draft) -> Draft {
        let words = draft.words.map { word in
            guard word.origin == .devanagari else { return word }
            let shape = WordShape(word.text)
            guard shape.core.allSatisfy({ !$0.isUppercase }), let form = forms[Romaniser.soundKey(shape.core)]
            else { return word }
            var written = word
            written.text = shape.replacingCore(with: form)
            return written
        }
        return Draft(words: words)
    }

    /// The honorifics and kinship words said after a name; they stay lower case.
    static let tailWords: Set<String> = Set(
        KinshipWords.hindiNameTails.map {
            Romaniser.soundKey($0)
        })

    /// The weekdays as a typist writes them, romanised by the same rules as the words they must match.
    static let weekdays: [String] = [
        "सोमवार", "मंगलवार", "बुधवार", "गुरुवार", "बृहस्पतिवार", "शुक्रवार", "शनिवार", "रविवार", "इतवार",
    ].map { Romaniser.romanised($0).capitalized }

    /// Whether an entry is one Latin word written with a leading capital and no other capital: a given name, a surname or a place.
    static func isCasedName(_ entry: String) -> Bool {
        guard entry.count >= 2, entry.allSatisfy({ $0.isLetter && $0.isASCII }),
            let first = entry.first, first.isUppercase
        else { return false }
        return entry.dropFirst().allSatisfy(\.isLowercase)
    }

    /// The words of `entries` written as names that are not ordinary words and not listed romanised Hindi: "Kal" stays tomorrow.
    static func names(_ entries: [String]) -> [String] {
        entries.flatMap { WordTokens.words($0, .display) }.filter {
            isCasedName($0) && !GeneralVocabulary.isOrdinary($0) && !LoanwordRestoration.isRomanisedHindi($0)
        }
    }
}
