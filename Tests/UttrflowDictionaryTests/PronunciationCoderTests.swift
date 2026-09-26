// Tests for addressing a spelling the English coder cannot speak.

import Testing

@testable import UttrflowDictionary

@Suite("Addressing a spelling")
struct PronunciationCoderTests {
    /// Where the metaphone can speak, it is still the only address: nothing about English changes.
    @Test(
        "keys an English spelling exactly as the metaphone does",
        arguments: ["Uttrflow", "kubectl", "caf\u{00E9}", "R2D2", "Nikhil"])
    func keysEnglishAsBefore(word: String) {
        #expect(PronunciationCoder.keys(for: word) == DoubleMetaphone.code(for: word).keys)
        #expect(!PronunciationCoder.keys(for: word).isEmpty)
    }

    /// A script the coder emits nothing for is addressed by its own spelling rather than dropped.
    @Test(
        "keys a spelling with no English letters on the spelling itself",
        arguments: [
            "\u{5317}\u{4EAC}", "\u{041C}\u{043E}\u{0441}\u{043A}\u{0432}\u{0430}", "2024",
        ])
    func keysOtherScriptsOnTheSpelling(word: String) {
        #expect(DoubleMetaphone.code(for: word).keys.isEmpty, "the metaphone is silent for this word")
        #expect(PronunciationCoder.keys(for: word).count == 1)
    }

    /// A Devanagari spelling also gets the keys of its romanisation, so a Latin entry can meet it.
    @Test("keys a Devanagari spelling on its romanisation as well as itself")
    func keysDevanagariOnItsRomanisation() {
        let devanagari = "\u{0928}\u{0935}\u{0940}\u{0928}"  // नवीन, "Naveen"
        #expect(DoubleMetaphone.code(for: devanagari).keys.isEmpty, "the metaphone is silent for Devanagari")
        let keys = PronunciationCoder.keys(for: devanagari)
        #expect(keys.contains(PronunciationCoder.spellingKey(for: devanagari)))
        #expect(Set(keys).isSuperset(of: DoubleMetaphone.code(for: "Naveen").keys))
    }

    /// A Latin entry and the Devanagari rendering of the same name share a key.
    @Test("meets a Latin entry from a Devanagari spelling of the same name")
    func meetsALatinEntryFromDevanagari() {
        let devanagari = "\u{0930}\u{0918}\u{0941}\u{0928}\u{093E}\u{0925}"  // रघुनाथ, "Raghunath"
        let latin = "Raghunath"
        #expect(
            !Set(PronunciationCoder.keys(for: devanagari)).isDisjoint(
                with: PronunciationCoder.keys(for: latin)))
    }

    /// पहुँच and पहुंच are the same word spelled with chandrabindu and anusvara; they must share a key.
    @Test("folds chandrabindu and anusvara into the same spelling key")
    func foldsChandrabinduAndAnusvara() {
        let chandrabindu = "\u{092A}\u{0939}\u{0941}\u{0901}\u{091A}"  // पहुँच
        let anusvara = "\u{092A}\u{0939}\u{0941}\u{0902}\u{091A}"  // पहुंच
        #expect(
            PronunciationCoder.spellingKey(for: chandrabindu) == PronunciationCoder.spellingKey(for: anusvara)
        )
    }

    @Test("folds case and accents into one key, so a word is not filed twice")
    func foldsCaseAndAccents() {
        #expect(
            PronunciationCoder.spellingKey(for: "M\u{00F6}ller")
                == PronunciationCoder.spellingKey(for: "moller"))
        #expect(PronunciationCoder.spellingKey(for: "\u{5317}\u{4EAC}!") == "\u{5317}\u{4EAC}")
    }

    /// Nothing can address a spelling with no letter and no digit in it, and pretending otherwise would lie.
    @Test("has no key at all for a spelling that is only punctuation")
    func punctuationHasNoKey() {
        #expect(PronunciationCoder.keys(for: "!!!").isEmpty)
        #expect(PronunciationCoder.keys(for: "").isEmpty)
    }
}
