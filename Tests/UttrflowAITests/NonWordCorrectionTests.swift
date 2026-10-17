import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// A word heard as letters nobody writes, sounding like an entry the user added. See Docs/ai-correction-thresholds.md.
@Suite("Non-word correction")
struct NonWordCorrectionTests {
    /// The engine under test.
    private let engine = WordCorrectionEngine()
    /// The shared fixture dictionary, every entry added by the user.
    private let index = CorrectionFixtures.index

    /// An index over these words, each with the origin given.
    private static func index(_ words: [String], origin: WordOrigin = .added) -> PhoneticIndex {
        PhoneticIndex(
            entries: words.map {
                DictionaryEntry(word: $0, origin: origin, firstSeen: Date(timeIntervalSince1970: 0))
            })
    }

    @Test(
        "respells a non-word as the added entry it sounds like, at any score",
        arguments: [0.2, 0.55, 0.92])
    func respellsANonWord(confidence: Double) throws {
        let utterance = CorrectionFixtures.spoken(
            "we cache every session in readees for an hour", sure: confidence)
        let proposals = engine.proposals(for: utterance, against: index)
        #expect(proposals.count == 1)
        let only = try #require(proposals.first)
        #expect(only.heard == "readees")
        #expect(only.replacement == "Redis")
        #expect(only.wordRange == 5..<6)
        #expect(only.heardConfidence == confidence)
        #expect(only.reason == .heardAsNonWord)
    }

    @Test("keeps the punctuation the recogniser hung on the non-word out of the lookup")
    func respellsANonWordBeforePunctuation() throws {
        let utterance = CorrectionFixtures.spoken("the dashboards all live in grafna, not here")
        let proposals = engine.proposals(for: utterance, against: index)
        #expect(proposals.count == 1)
        let only = try #require(proposals.first)
        #expect(only.heard == "grafna,")
        #expect(only.replacement == "Grafana")
        #expect(only.reason == .heardAsNonWord)
    }

    /// The English words beside them in the restraint corpus: "readies" and "griffin" are words, so they stay.
    @Test(
        "leaves an English word that sounds like an added entry", arguments: ["readies", "griffin", "clawed"])
    func leavesAnEnglishWord(word: String) {
        let utterance = CorrectionFixtures.spoken("we saw that \(word) again this morning")
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// Romanised Hindi has content words no list holds: "nikaal" is a spelling of a listed verb, "kitaab" of no listed word.
    @Test("leaves a non-word in a sentence with romanised Hindi in it")
    func leavesAHindiSentence() {
        let utterance = CorrectionFixtures.spoken("wo purani kitaab nikaal kar dekh lena")
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// Letters spoken as their names are an abbreviation, a unit or a code; no name's sound claims them.
    @Test(
        "leaves doubted spelled letters, even beside a name they loosely sound like",
        arguments: [
            ("bring snacks e g chips", "Isha"), ("we need it a s a p", "Zoe"),
            ("the drive holds two t b of photos", "Deepa"), ("the hum is sixty h z", "Zoe"),
            ("r and d owns the roadmap", "Dana"),
        ])
    func leavesSpelledLetters(sentence: String, name: String) {
        let utterance = CorrectionFixtures.spoken(sentence, sure: 0.3)
        #expect(engine.proposals(for: utterance, against: Self.index([name])).isEmpty)
    }

    /// Capitals past the first letter are written on purpose, so "YOYO" is not respelt as an entry that sounds like it.
    @Test("leaves a word written in capitals")
    func leavesCapitals() {
        let utterance = CorrectionFixtures.spoken("we cache every session in READEES for an hour")
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    @Test("an entry the user did not add is not taken on a non-word alone")
    func needsAnAddedEntry() {
        let utterance = CorrectionFixtures.spoken("we cache every session in readees for an hour")
        #expect(
            engine.proposals(for: utterance, against: Self.index(["Redis"], origin: .learned)).isEmpty)
    }

    @Test("two added entries that both sound like it leave the word as heard")
    func abstainsBetweenTwoEntries() {
        let utterance = CorrectionFixtures.spoken("we cache every session in readees for an hour")
        #expect(engine.proposals(for: utterance, against: Self.index(["Redis", "Reddis"])).isEmpty)
    }

    @Test("the screen writing the heard spelling keeps it")
    func theScreenKeepsTheHeardSpelling() {
        let utterance = CorrectionFixtures.spoken("we cache every session in readees for an hour")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showing("readees notes")
            ).isEmpty)
    }

    @Test("a pairing the user undid is refused")
    func anUndonePairingIsRefused() {
        let utterance = CorrectionFixtures.spoken("we cache every session in readees for an hour")
        var budget = CorrectionBudget()
        let verdict = engine.verdict(
            for: utterance, against: index, spending: &budget, hearing: utterance.words.count,
            pairs: [ConfusionPairs.key(heard: "readees", meant: "Redis"): .vetoed])
        #expect(verdict.proposals.isEmpty)
    }

    @Test("still spends the one-in-five budget")
    func spendsTheBudget() {
        let utterance = CorrectionFixtures.spoken("readees and grafna")
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// A spelling the recogniser committed to as a name: capitalised in mid-sentence and scored surely.
    @Test(
        "keeps a capitalised name inside a sentence that the recogniser heard surely",
        arguments: [
            ("Please ask Meera about the report today", "Mira"),
            ("Please ask Zoya about the report today", "Zoe"),
            ("Hi Meera, thanks for the report", "Mira"),
        ])
    func keepsASurelyHeardName(sentence: String, entry: String) {
        let utterance = CorrectionFixtures.spoken(sentence, sure: 0.95)
        #expect(engine.proposals(for: utterance, against: Self.index([entry])).isEmpty)
    }

    @Test("still respells that name when the recogniser was unsure of it")
    func respellsAnUnsureName() throws {
        let utterance = CorrectionFixtures.spoken("Please ?Meera about the report today")
        let proposals = engine.proposals(for: utterance, against: Self.index(["Mira"]))
        #expect(try #require(proposals.first).replacement == "Mira")
    }

    @Test(
        "still respells a capitalised non-word that opens a sentence",
        arguments: ["Meera sent the report today", "Thanks for that. Meera sent the report today"])
    func respellsASentenceOpening(sentence: String) throws {
        let utterance = CorrectionFixtures.spoken(sentence, sure: 0.95)
        let proposals = engine.proposals(for: utterance, against: Self.index(["Mira"]))
        #expect(try #require(proposals.first).replacement == "Mira")
    }

    /// "Rao" is no English word, but the dictionary writes it inside `Deepak Rao`, so the user writes it.
    @Test(
        "leaves a word the dictionary writes inside a longer entry",
        arguments: [0.2, 0.95])
    func leavesAWordOfALongerEntry(confidence: Double) {
        let utterance = CorrectionFixtures.spoken(
            "Deepak and Rao went to the market", sure: confidence)
        #expect(
            engine.proposals(for: utterance, against: Self.index(["Deepak Rao", "Ray"])).isEmpty)
    }

    @Test("still respells a non-word that no longer entry writes")
    func respellsWhenNoLongerEntryWritesIt() throws {
        let utterance = CorrectionFixtures.spoken("we cache every session in readees for an hour")
        let proposals = engine.proposals(
            for: utterance, against: Self.index(["Redis", "Deepak Rao"]))
        #expect(try #require(proposals.first).replacement == "Redis")
    }
}
