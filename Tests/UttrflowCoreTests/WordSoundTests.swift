// Tests for the sound keys, the spelling rules behind them and the distance questions callers ask.

import Testing

@testable import UttrflowCore

@Suite("A word's sound: keys from the lexicon and the spelling rules, and how far two sounds are")
struct WordSoundTests {
    private static let listing = """
        hear HH IY1 R
        here HH IY1 R
        here's HH IY1 R Z
        in IH0 N
        in. IH1 N
        utter AH1 T ER0
        flow F L OW1
        mod M AA1 D
        made M EY1 D
        cash K AE1 SH
        """

    private let lexicon = PhonemeLexicon(
        listing: Self.listing, classes: PhonemeLexicon.bundledClasses,
        spellingRules: PhonemeLexicon.bundledSpellingRules, keyRules: PhonemeLexicon.bundledKeyRules)

    @Test("A run of listed words keys like the unlisted name closed up, across an r-coloured vowel")
    func runMeetsTheName() {
        let run = WordSound(of: "utter flow", in: lexicon)
        let name = WordSound(of: "Uttrflow", in: lexicon)
        #expect(run.sounds(like: name))
        #expect(!run.isSilent)
    }

    @Test("Digits and punctuation alone make no sound and have no key")
    func silentText() {
        for text in ["", "2024", "--", "\u{0915}"] {
            #expect(WordSound(of: text, in: lexicon).isSilent, "\(text)")
        }
    }

    @Test("A rule with a second reading files the word under both: soft and hard g")
    func secondReading() {
        #expect(lexicon.spelledSounds(of: "gemma").count == 2)
        #expect(WordSound(of: "Gemma", in: lexicon).sounds(like: WordSound(of: "Kemma", in: lexicon)))
        #expect(lexicon.spelledSounds(of: "tamp").count == 1)
    }

    @Test("Start, end, next-letter and silent rules apply only where they fit")
    func ruleContexts() {
        let knight = lexicon.spelledSounds(of: "knight")
        let night = lexicon.spelledSounds(of: "night")
        #expect(knight == night)
        #expect(lexicon.spelledSounds(of: "hhh").isEmpty)
        #expect(lexicon.spelledSounds(of: "cell") == lexicon.spelledSounds(of: "sel"))
        #expect(!lexicon.spelledSounds(of: "e").isEmpty)
        #expect(lexicon.spelledSounds(of: "tame").count == 1)
    }

    @Test("Distance is the lexicon's alone for listed words, and the spelling's for any other")
    func distances() {
        #expect(lexicon.soundDistance("hear", "here") == 0)
        #expect(lexicon.soundDistance("mod", "made") == 0.5)
        #expect(lexicon.soundsNear("Cash", "kash"))
        #expect(!lexicon.soundsNear("cash", "utter"))
        #expect(lexicon.soundDistance("cash", "2024") == nil)
    }

    @Test("Homophones are other listed words said exactly alike, never the word with a mark on it")
    func homophones() {
        #expect(lexicon.soundsSame("Hear", "HERE"))
        #expect(!lexicon.soundsSame("hear", "hear"))
        #expect(!lexicon.soundsSame("hear", "unlisted"))
        #expect(lexicon.homophones(of: "hear") == ["here"])
        #expect(lexicon.homophones(of: "in").isEmpty)
        #expect(lexicon.soundsSame("here", "here\u{2019}s") == false)
    }

    @Test("A tally counts every sound worked out while it is bound")
    func tallyCounts() {
        let tally = EncodingTally()
        WordSound.$tally.withValue(tally) {
            _ = WordSound(of: "hear", in: lexicon)
            _ = WordSound(of: "here")
        }
        #expect(tally.count == 2)
    }

    @Test("The shared lexicon is the bundled one")
    func sharedIsBundled() {
        #expect(PhonemeLexicon.shared.holds("their"))
        #expect(WordSound(of: "their").sounds(likeAnyOf: Set(WordSound(of: "there").keys)))
    }
}
