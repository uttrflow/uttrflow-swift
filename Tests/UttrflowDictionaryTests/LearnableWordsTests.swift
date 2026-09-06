// Tests for the learning rules and the sighting tally.

import UttrflowCore
import UttrflowTestSupport
import Testing

@testable import UttrflowDictionary

@Suite("Words a general model already knows")
struct GeneralVocabularyTests {
    /// The rule the feature is gated on: learning "the" spends a slot on a word no recogniser gets wrong.
    @Test(
        "Refuses ordinary English",
        arguments: [
            "the", "and", "meeting", "tomorrow", "project", "please", "document", "email",
            "morning", "review", "team",
        ])
    func refusesOrdinaryEnglish(_ word: String) {
        #expect(!GeneralVocabulary.isWorthLearning(word))
    }

    /// The half an English-only filter would miss; Uttrflow does Hinglish.
    @Test(
        "Refuses ordinary romanised Hinglish",
        arguments: ["nahi", "bilkul", "matlab", "theek", "yaar", "kaam", "kitna", "chahiye"])
    func refusesOrdinaryHinglish(_ word: String) {
        #expect(!GeneralVocabulary.isWorthLearning(word))
    }

    /// The words the dictionary exists for must still get through, a Hinglish one included.
    @Test(
        "Keeps the words a general model has never heard",
        arguments: [
            "Uttrflow", "pgvector", "kubectl", "Valkey", "Nikhil", "PaymentSheet", "Bandra",
            "Chandrashekhar", "SQL",
        ])
    func keepsTheUnusual(_ word: String) {
        #expect(GeneralVocabulary.isWorthLearning(word))
    }

    @Test("Refuses what is too short to be a word, or is not one")
    func refusesTheShapeless() {
        #expect(!GeneralVocabulary.isWorthLearning("ok"))
        #expect(!GeneralVocabulary.isWorthLearning("s"))
        // A date or a version is on screen constantly and is never a word.
        #expect(!GeneralVocabulary.isWorthLearning("2024"))
        #expect(!GeneralVocabulary.isWorthLearning("...."))
    }

    /// A word is the same word however it is capitalised, and a title is full of capitals.
    @Test("Reads a word the same whatever its case")
    func caseDoesNotMatter() {
        #expect(!GeneralVocabulary.isWorthLearning("Meeting"))
        #expect(!GeneralVocabulary.isWorthLearning("TOMORROW"))
        #expect(GeneralVocabulary.knows("The"))
    }

    @Test("Offers the homophone a recogniser confuses an ordinary word with")
    func offersAHomophone() {
        #expect(GeneralVocabulary.wordsSounding(like: "there").contains("their"))
        #expect(GeneralVocabulary.wordsSounding(like: "their").contains("there"))
    }

    /// A common word that merely rhymes is a real word and no reading of anything, so the opening must match too.
    @Test("Offers nothing for a word whose only matches open differently")
    func refusesARhyme() {
        #expect(GeneralVocabulary.wordsSounding(like: "cash").isEmpty)
        #expect(GeneralVocabulary.wordsSounding(like: "reader").isEmpty)
    }

    @Test("Never offers the word it was asked about, whatever its case")
    func neverOffersItself() {
        #expect(!GeneralVocabulary.wordsSounding(like: "There").contains("there"))
    }

    @Test("Offers nothing for a word no ordinary word sounds like")
    func offersNothingForAStranger() {
        #expect(GeneralVocabulary.wordsSounding(like: "asyncpg").isEmpty)
        #expect(GeneralVocabulary.wordsSounding(like: "").isEmpty)
    }

    @Test("Offers no more than the cap, so one sound cannot fill a prompt line")
    func capsWhatItOffers() {
        for word in ["there", "note", "kar", "hai"] {
            #expect(GeneralVocabulary.wordsSounding(like: word).count <= GeneralVocabulary.maximumPerSound)
        }
    }
}

@Suite("Terms that were on screen and were said")
struct SeenAndSaidTests {
    /// The case the path exists for: spelt closed on screen, said open by the speaker.
    @Test("Finds a camel-cased term a speaker said as two words")
    func findsTheClosedUpSpelling() {
        let found = LearnableWords.seenAndSaid(
            heard: "add a total to the payment sheet",
            seeing: .fixture(documentName: "PaymentSheet.swift — Acme"))
        #expect(found == ["PaymentSheet"])
    }

    /// The app's name is on screen for every dictation in it and would corroborate itself at once.
    @Test("Never reads the application's own name")
    func ignoresTheApplicationName() {
        let found = LearnableWords.seenAndSaid(
            heard: "pgvector is what we use",
            seeing: AppContext(applicationName: "pgvector", documentName: "notes"))
        #expect(found.isEmpty)
    }

    /// A selection is the text this dictation is about to overwrite, not context.
    @Test("Never reads the selection, which is the text being replaced")
    func ignoresTheSelection() {
        let found = LearnableWords.seenAndSaid(
            heard: "pgvector",
            seeing: .fixture(documentName: "notes", selectedText: "pgvector"))
        #expect(found.isEmpty)
    }

    @Test("Refuses an ordinary word even when it was both on screen and said")
    func refusesTheOrdinary() {
        let found = LearnableWords.seenAndSaid(
            heard: "meeting notes for tomorrow",
            seeing: .fixture(documentName: "Meeting notes — tomorrow"))
        #expect(found.isEmpty)
    }

    @Test("Refuses a term on screen that nobody said")
    func refusesTheUnspoken() {
        let found = LearnableWords.seenAndSaid(
            heard: "let us start", seeing: .fixture(documentName: "pgvector migration"))
        #expect(found.isEmpty)
    }

    @Test("Has nothing to read when macOS gave us no title")
    func noTitle() {
        #expect(
            LearnableWords.seenAndSaid(
                heard: "pgvector", seeing: AppContext(applicationName: "Xcode")
            ).isEmpty)
    }

    @Test("Has nothing to match when nothing was heard")
    func nothingHeard() {
        #expect(LearnableWords.seenAndSaid(heard: "", seeing: .fixture(documentName: "pgvector")).isEmpty)
    }

    /// A title that says the word twice is one sighting, or a window could learn itself in one dictation.
    @Test("Counts a term once however often the title repeats it")
    func dedupesTheTitle() {
        let found = LearnableWords.seenAndSaid(
            heard: "pgvector again", seeing: .fixture(documentName: "pgvector — pgvector"))
        #expect(found == ["pgvector"])
    }
}

@Suite("A dictation made over a selection")
struct CorrectedWordTests {
    /// The user highlighted the wrong spelling, said the word again, and let the new spelling stand.
    @Test("Learns the spelling that replaced a homophone of itself")
    func learnsTheReplacement() {
        #expect(LearnableWords.corrected(over: "utter flow", wrote: "Uttrflow") == "Uttrflow")
        #expect(LearnableWords.corrected(over: "Nikkel", wrote: "Nikhil.") == "Nikhil")
        #expect(LearnableWords.corrected(over: "payment sheet", wrote: "PaymentSheet") == "PaymentSheet")
    }

    @Test("Refuses a long selection, which is a rewrite and not a correction")
    func refusesARewrite() {
        #expect(
            LearnableWords.corrected(
                over: "the utter flow release", wrote: "the Uttrflow release") == nil)
    }

    @Test("Refuses a long replacement for the same reason")
    func refusesALongReplacement() {
        #expect(LearnableWords.corrected(over: "Uttrflow", wrote: "utter flow is here") == nil)
    }

    @Test("Refuses two phrases that do not sound like each other")
    func refusesADifferentWord() {
        #expect(LearnableWords.corrected(over: "kubectl", wrote: "pgvector") == nil)
    }

    /// Two phrases sharing a word are two phrases; whole sound against whole sound.
    @Test("Refuses two phrases that merely share a word")
    func refusesASharedWord() {
        #expect(LearnableWords.corrected(over: "Uttrflow build", wrote: "Uttrflow ship") == nil)
    }

    @Test("Refuses a replacement that is the same word again")
    func refusesTheSameSpelling() {
        #expect(LearnableWords.corrected(over: "Uttrflow", wrote: "Uttrflow") == nil)
        // Capitals alone are not a mis-hearing being reported.
        #expect(LearnableWords.corrected(over: "uttrflow", wrote: "Uttrflow") == nil)
    }

    /// "there" and "their" are one sound; an ordinary word in the index breaks a sentence that was right.
    @Test("Refuses an ordinary English homophone")
    func refusesAnOrdinaryHomophone() {
        #expect(LearnableWords.corrected(over: "there", wrote: "their") == nil)
        #expect(LearnableWords.corrected(over: "to the", wrote: "too they") == nil)
    }

    @Test("Refuses a replacement whose every word is ordinary, even beside a rare one")
    func refusesAPartlyOrdinaryPhrase() {
        #expect(LearnableWords.corrected(over: "the utterflow", wrote: "the Uttrflow") == nil)
    }

    @Test("Has nothing to correct when nothing was selected")
    func refusesWithoutASelection() {
        #expect(LearnableWords.corrected(over: nil, wrote: "Uttrflow") == nil)
        #expect(LearnableWords.corrected(over: "   ", wrote: "Uttrflow") == nil)
    }

    /// A run of letters that makes no sound has no key, so it could never be found again.
    @Test("Refuses a replacement that makes no sound at all")
    func refusesASilentReplacement() {
        #expect(DoubleMetaphone.code(for: "hhh").isSilent)
        #expect(LearnableWords.corrected(over: "hhhh", wrote: "hhh") == nil)
    }
}

@Suite("The tally of what keeps turning up")
struct SightingLedgerTests {
    @Test("Keeps a term only once it has turned up in three separate dictations")
    func threeSightings() {
        var ledger = SightingLedger()
        #expect(ledger.record(["pgvector"]).isEmpty)
        #expect(ledger.record(["pgvector"]).isEmpty)
        #expect(ledger.record(["pgvector"]) == ["pgvector"])
    }

    /// The spelling first seen wins, so three dictations cannot leave the term spelt the last way seen.
    @Test("Keeps the spelling it first saw")
    func keepsTheFirstSpelling() {
        var ledger = SightingLedger()
        _ = ledger.record(["PgVector"])
        _ = ledger.record(["pgvector"])
        #expect(ledger.record(["PGVECTOR"]) == ["PgVector"])
    }

    /// A term just learnt must leave the tally, or the next sighting learns it twice.
    @Test("Forgets a term the moment it is kept")
    func stopsCountingWhatItKept() {
        var ledger = SightingLedger()
        for _ in 1...3 { _ = ledger.record(["pgvector"]) }
        #expect(ledger.record(["pgvector"]).isEmpty)
    }

    @Test("Counts each term on its own")
    func countsSeparately() {
        var ledger = SightingLedger()
        _ = ledger.record(["pgvector", "Valkey"])
        _ = ledger.record(["pgvector"])
        #expect(ledger.record(["pgvector", "Valkey"]) == ["pgvector"])
    }

    /// Half-counted evidence is the app's inference about the user, and the reset throws it away too.
    @Test("Throws the whole tally away when asked")
    func forgetsEverything() {
        var ledger = SightingLedger()
        _ = ledger.record(["pgvector"])
        _ = ledger.record(["pgvector"])
        ledger.forgetEverything()
        #expect(ledger.record(["pgvector"]).isEmpty)
    }

    /// A tally that grew with everything glanced at would be a leak made of window titles.
    @Test("Stays inside its bound, dropping the weakest evidence first")
    func prunesToTheBound() {
        var ledger = SightingLedger()
        _ = ledger.record(["Uttrflow"])
        _ = ledger.record(["Uttrflow"])
        _ = ledger.record((1...SightingLedger.maximumPending * 2).map { "Term\($0)word" })

        // The twice-seen term survived the cull, so one more sighting is enough.
        #expect(ledger.record(["Uttrflow"]) == ["Uttrflow"])
    }
}
