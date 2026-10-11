// The word-by-word check that a romanised rewrite of Hindi changed no word the speaker said.
import UttrflowCore
import UttrflowDictionary

extension MeaningPreservationGuard {
    /// One word of a romanised text: as written, and as the key two spellings of it share.
    struct RomanisedWord: Equatable {
        let word: String
        let key: String
    }

    /// The first content word the rewrite substituted, dropped or added against the romanised draft, in order, or `nil`. See `Docs/latin-output.md`.
    static func changedWord(said: String, written: String) -> String? {
        let spoken = withoutStammers(romanisedWords(said))
        let spelt = withoutStammers(romanisedWords(written))
        // A key either side spells as a grammar word is left out of both, so "arre" goes with the English "are".
        let grammar = Set((spoken + spelt).filter { isGrammarWord($0.word) }.map(\.key))
        let heard = spoken.filter { !grammar.contains($0.key) }
        let wrote = spelt.filter { !grammar.contains($0.key) }
        let alignment = WordErrorRate.measure(reference: heard.map(\.key), hypothesis: wrote.map(\.key))
            .alignment
        var next = (heard: 0, wrote: 0)
        for operation in alignment {
            switch operation {
            case .match:
                next = (next.heard + 1, next.wrote + 1)
            case .substitution:
                let (spoken, spelt) = (heard[next.heard].word, wrote[next.wrote].word)
                next = (next.heard + 1, next.wrote + 1)
                guard WordForms.sameRomanisedForm(spoken, spelt) || isRespelling(spoken, as: spelt) else {
                    return spoken
                }
            case .deletion:
                return heard[next.heard].word
            case .insertion:
                return wrote[next.wrote].word
            }
        }
        return nil
    }

    /// The words of a romanised text, a filler dropped, a number word keyed as its digits and the rest by sound.
    static func romanisedWords(_ text: String) -> [RomanisedWord] {
        WordShape.words(text).compactMap { word in
            guard !FillersPass.fillerWords.contains(word) else { return nil }
            if let digits = numberWords[word] { return RomanisedWord(word: digits, key: digits) }
            return RomanisedWord(
                word: word, key: word.allSatisfy(\.isNumber) ? word : Romaniser.soundKey(word))
        }
    }

    /// Removes only adjacent repetitions the stammer pass would remove.
    static func withoutStammers(_ words: [RomanisedWord]) -> [RomanisedWord] {
        var kept: [RomanisedWord] = []
        for word in words {
            guard let previous = kept.last, word.key == previous.key else {
                kept.append(word)
                continue
            }
            let spelling = word.word.lowercased()
            if (FunctionWords.holds(spelling) || isGrammarWord(spelling))
                && !StammersPass.legitimateDoubles.contains(spelling)
            {
                continue
            }
            if numberWords[spelling] != nil, numberWords[previous.word.lowercased()] != nil {
                continue
            }
            kept.append(word)
        }
        return kept
    }

    /// Whether the rewrite wrote a loanword the rules romanised in its English spelling: "ticket" for the rules' "tikat".
    static func isRespelling(_ spoken: String, as spelt: String) -> Bool {
        LoanwordRestoration.isRespelling(spoken, as: spelt)
    }

    /// Whether a word only ties the sentence together, so adding or dropping it changes no content: never a number, a negation or a Hindi pronoun.
    static func isGrammarWord(_ word: String) -> Bool {
        guard !word.contains(where: \.isNumber), !isNegation(word) else { return false }
        let key = Romaniser.soundKey(word)
        guard WordForms.hindiPronouns[key] == nil else { return false }
        return FunctionWords.holds(word) || HindiWords.grammarWords.contains(key)
    }
}
