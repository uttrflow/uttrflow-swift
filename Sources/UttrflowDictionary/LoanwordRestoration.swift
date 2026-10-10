// Whether a word the romaniser spelt by sound is an English word, and which. See `Docs/latin-output.md`.
public import UttrflowCore

/// Puts back the English spelling of a loanword the syllable rules spelt by sound, from the shipped technical lexicon and the person's own words.
public struct LoanwordRestoration: Sendable {
    /// The English spellings a restoration may produce, the person's own first, each with its sound worked out once.
    let english: [[ReadingKey]]

    /// The source is the shipped technical lexicon plus `personal`, the person's dictionary words; no other list.
    public init(personal: [String] = []) {
        // An acronym is said letter by letter, a command typed at a prompt and an annotation opens a comment, so none is a word said inside a sentence: "kal" is not "CLI".
        let said = TechnicalLexicon.terms.filter { ![.acronym, .command, .annotation].contains($0.category) }
        var seen: Set<String> = []
        english = [personal, said.map(\.id)].map { written in
            written.compactMap { spelling in
                guard spelling.allSatisfy(\.isLetter), spelling.allSatisfy(\.isASCII),
                    seen.insert(spelling.lowercased()).inserted
                else { return nil }
                return ReadingKey(spelling)
            }
        }
    }

    /// The English spelling to write for a romanised word, or nil when it is vetoed or more than one word qualifies; a word of the person's own is asked first.
    public func restored(_ romanised: String) -> String? {
        guard !Self.isRomanisedHindi(romanised) else { return nil }
        let heard = romanised.lowercased()
        // व is one letter for both "v" and "w", and the rules write "w": "mewan" is heard as "mevan" too.
        let sounds = Set([heard, String(heard.map { $0 == "w" ? "v" : $0 })])
        for (rank, source) in english.enumerated() {
            // A shipped term is not the person's own word, so it needs a longer shared key: "baal" is not "bool".
            let fewestSounds = rank == 0 ? 2 : 3
            let matches = source.filter { key in
                sounds.contains { sound in
                    Self.isRespelling(sound, as: key.word)
                        && Self.sharesKey(sound, key.sound, ofAtLeast: fewestSounds)
                }
            }
            // A word already spelt as a source word is that word, in the source's own casing: "kotlin" is "Kotlin".
            if let spelt = matches.first(where: { $0.closed == heard }) { return spelt.word }
            if !matches.isEmpty { return matches.count == 1 ? matches.first?.word : nil }
        }
        return nil
    }

    /// The draft with each word the romaniser spelt by sound written as the one English word it is, and every other word untouched.
    public func restoring(_ draft: Draft) -> Draft {
        let words = draft.words.map { word in
            guard word.origin == .devanagari, let english = restored(word.text) else { return word }
            var written = word
            written.text = english
            return written
        }
        return Draft(words: words, confidencesAreReal: draft.confidencesAreReal)
    }

    /// Whether the romanised word shares a sound key of at least this many sounds with an English spelling.
    static func sharesKey(_ romanised: String, _ english: WordSound, ofAtLeast sounds: Int) -> Bool {
        WordSound(of: romanised).keys.contains { $0.count >= sounds && english.keys.contains($0) }
    }

    /// Whether a word is in one of the romanised Hindi tables, which veto any restoration of it: "kal" never becomes "call".
    public static func isRomanisedHindi(_ word: String) -> Bool {
        let key = Romaniser.soundKey(word.lowercased())
        if hindiKeys.contains(key) { return true }
        // An infinitive of a listed verb stem: "bolna" is "bol".
        return ["na", "ne", "ni"].contains { ending in
            key.hasSuffix(ending) && HindiWords.verbStems.contains(String(key.dropLast(ending.count)))
        }
    }

    /// Every word of the romanised Hindi tables, by sound key, so "daadi" is vetoed by the listed "dadi".
    static let hindiKeys: Set<String> = Set(
        (HindiWords.spellings + KinshipWords.hindiWords).map { Romaniser.soundKey($0) })

    /// Whether `spelt` is `spoken` written another way: a shared sound key of at least two sounds, within one phoneme, and not one ordinary word for another.
    public static func isRespelling(_ spoken: String, as spelt: String) -> Bool {
        guard !spoken.contains(where: \.isNumber), !spelt.contains(where: \.isNumber) else { return false }
        guard !ReadingRestraint.isOrdinaryCollision(spelt, heard: spoken) else { return false }
        let heard = WordSound(of: spoken)
        let spelling = WordSound(of: spelt)
        // One sound says too little to call two words one.
        return heard.keys.contains { $0.count > 1 && spelling.keys.contains($0) }
            && ReadingRestraint.soundsNear(spelt, heard: spoken)
    }
}
