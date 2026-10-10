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
        #expect(GeneralVocabulary.isOrdinary("The"))
    }

    /// A function word carries the sentence's structure, so its homophone is a change of meaning rather than a reading.
    @Test(
        "Offers no homophone where either word is a function word",
        arguments: [("there", "their"), ("their", "there"), ("then", "than"), ("one", "on")])
    func refusesAFunctionWordHomophone(heard: String, homophone: String) {
        #expect(!GeneralVocabulary.wordsSounding(like: heard).contains(homophone))
    }

    /// Refused at the query, not only filtered from the answer, so nothing at all comes back for one.
    @Test("Offers nothing at all for a function word", arguments: ["there", "their", "than", "on"])
    func offersNothingForAFunctionWord(heard: String) {
        #expect(GeneralVocabulary.wordsSounding(like: heard).isEmpty)
    }

    @Test("Never offers a function word as the reading of anything")
    func neverOffersAFunctionWord() {
        for word in ["then", "one", "hear", "note", "kar", "hai", "wait", "mail", "week"] {
            #expect(GeneralVocabulary.wordsSounding(like: word).allSatisfy { !FunctionWords.holds($0) })
        }
    }

    /// Two words that both carry meaning, sound alike and open alike are still a reading worth offering.
    @Test("Still offers a homophone between two words that carry meaning")
    func offersAContentHomophone() {
        #expect(GeneralVocabulary.wordsSounding(like: "hear").contains("here"))
    }

    /// A common word that merely rhymes is a real word and no reading of anything, so the opening must match too.
    @Test("Offers nothing for a word whose only matches open differently")
    func refusesARhyme() {
        #expect(GeneralVocabulary.wordsSounding(like: "kash").isEmpty)
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

    @Test("Ignores title words already written correctly")
    func ignoresAlreadyCorrectSpellings() {
        #expect(
            LearnableWords.seenAndSaid(
                heard: "clear the inbox before lunch",
                seeing: .fixture(documentName: "Inbox (12) — Mail")
            ).isEmpty)
        #expect(
            LearnableWords.seenAndSaid(
                heard: "take a screenshot",
                seeing: .fixture(documentName: "Screenshot 2026-09-21")
            ).isEmpty)
    }

    /// These are not ordinary, since the recogniser splits them, so only the English-word test refuses them.
    @Test(
        "Ignores an English word the recogniser splits when it is heard as written",
        arguments: ["rebase", "refactor", "rollback", "timeout"])
    func ignoresAnEnglishWordHeardAsWritten(word: String) {
        #expect(!GeneralVocabulary.isOrdinary(word))
        #expect(
            LearnableWords.seenAndSaid(
                heard: "the \(word) failed again", seeing: .fixture(documentName: "\(word) notes")
            ).isEmpty)
    }

    @Test("Requires a changed spelling and rejects title abbreviations")
    func requiresDistinctSpelling() {
        for (title, heard) in [
            ("Inbox (12) — Mail", "clear the inbox before lunch"),
            ("IMG_4821.HEIC", "the image is too dark"),
            ("Spreadsheet1.xlsx", "the spreadsheet is ready"),
            ("Screenshot 2026-09-21", "take a screenshot"),
            ("a3f9c2e1d — fix login", "fix the login bug"),
        ] {
            #expect(LearnableWords.seenAndSaid(heard: heard, seeing: .fixture(documentName: title)).isEmpty)
        }
    }

    @Test("Learns distinct real terms from a window title")
    func keepsDistinctPersonalSpellings() {
        for (title, heard, expected) in [
            ("Zorvane — notes", "use Zorvain for this", "Zorvane"),
            ("PaymentSheet.swift", "add a total to the payment sheet", "PaymentSheet"),
            ("Chandrashekhar — notes", "ask Chandra Shekhar about it", "Chandrashekhar"),
            ("pgvector — README", "we use PG vector here", "pgvector"),
        ] {
            #expect(
                LearnableWords.seenAndSaid(heard: heard, seeing: .fixture(documentName: title))
                    == [expected])
        }
    }
}

/// The comparison as it reads with nothing reused: every span encoded again for every title term.
private func seenAndSaidByBruteForce(heard: String, title: String) -> [String] {
    let said = Utterance(heard: heard, confidence: 1).spans(upTo: PhoneticIndex.maximumWordsPerEntry)
    var found: [String] = []
    var already: Set<String> = []
    for term in LearnableWords.words(in: title, atMost: WorkingSet.maximumWordsOnScreen)
    where GeneralVocabulary.isWorthLearning(term) && already.insert(term.lowercased()).inserted {
        let sound = WordSound(of: term)
        if said.contains(where: {
            sound.sounds(like: WordSound(of: $0.text))
                && ReadingRestraint.soundsNear(term, heard: $0.text)
        }) {
            found.append(term)
        }
    }
    return found
}

/// Counts every encoding asked for, so the work is measured in calls rather than time.
private final class CountingEncoder: @unchecked Sendable {
    private(set) var calls = 0

    func encode(_ text: String) -> WordSound {
        calls += 1
        return WordSound(of: text)
    }
}

@Suite("Terms that were on screen and were said, encoded once")
struct SeenAndSaidEncodingTests {
    /// A long dictation under a title full of learnable terms, the shape the product of the two blew up on.
    private static let heard =
        Array(repeating: "calibrate the zorvaab and the zorvaac", count: 40).joined(separator: " ")
    private static let letters = Array("abcdefghijklmnopqrstuvwxyz")
    /// Sixty-four distinct invented terms, "Zorvaaa" to "Zorvalc", the most a title is read for.
    private static let title = (0..<64).map { "Zorva\(letters[$0 % 26])\(letters[$0 / 26])" }
        .joined(separator: " ")

    @Test("encodes each spoken span once and each title term once, not one per pairing")
    func encodingGrowsWithTheSum() {
        let spans = Utterance(heard: Self.heard, confidence: 1)
            .spans(upTo: PhoneticIndex.maximumWordsPerEntry).count
        let terms = LearnableWords.words(in: Self.title, atMost: WorkingSet.maximumWordsOnScreen)
            .filter(GeneralVocabulary.isWorthLearning).count
        let counter = CountingEncoder()

        _ = LearnableWords.seenAndSaid(
            heard: Self.heard, seeing: .fixture(documentName: Self.title), encoding: counter.encode)

        #expect(terms > 1)
        #expect(counter.calls == spans + terms)
    }

    @Test("finds exactly what comparing every pairing afresh finds, in the same order")
    func sameCandidatesAsBruteForce() {
        let found = LearnableWords.seenAndSaid(heard: Self.heard, seeing: .fixture(documentName: Self.title))

        #expect(!found.isEmpty)
        #expect(found == seenAndSaidByBruteForce(heard: Self.heard, title: Self.title))
    }

    @Test(
        "agrees with comparing every pairing afresh on the existing cases",
        arguments: [
            ("add a total to the payment sheet", "PaymentSheet.swift — Acme"),
            ("pgvector again", "pgvector — pgvector"),
            ("meeting notes for tomorrow", "Meeting notes — tomorrow"),
            ("let us start", "pgvector migration"),
        ])
    func sameCandidatesOnExistingCases(heard: String, title: String) {
        #expect(
            LearnableWords.seenAndSaid(heard: heard, seeing: .fixture(documentName: title))
                == seenAndSaidByBruteForce(heard: heard, title: title))
    }

    @Test("encodes no spoken span when no title term is worth comparing")
    func encodesNothingForAnOrdinaryTitle() {
        let counter = CountingEncoder()

        _ = LearnableWords.seenAndSaid(
            heard: Self.heard, seeing: .fixture(documentName: "Meeting notes"), encoding: counter.encode)

        #expect(counter.calls == 0)
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

    /// A single accidental re-dictation must not add an ordinary spelling or a correction to one.
    @Test("Refuses ordinary words and spelling fixes of ordinary words")
    func refusesOrdinarySpellings() {
        #expect(LearnableWords.corrected(over: "minute", wrote: "mint") == nil)
        #expect(LearnableWords.corrected(over: "recieve", wrote: "receive") == nil)
        #expect(LearnableWords.corrected(over: "seperate", wrote: "separate") == nil)
        #expect(LearnableWords.corrected(over: "adress", wrote: "address") == nil)
        #expect(LearnableWords.corrected(over: "occured", wrote: "occurred") == nil)
    }

    /// Editing "thik" to "theek" states a spelling preference between two listed spellings of one Hindi word.
    @Test("Learns the user's spelling of a listed Hindi word")
    func learnsAHindiSpellingPreference() {
        #expect(LearnableWords.corrected(over: "thik", wrote: "theek") == "theek")
        #expect(LearnableWords.corrected(over: "acha", wrote: "accha") == "accha")
    }

    @Test("Refuses a listed Hindi word that is not a spelling of the one it replaced")
    func refusesADifferentHindiWord() {
        #expect(LearnableWords.corrected(over: "theek", wrote: "thik hai") == nil)
        #expect(LearnableWords.corrected(over: "kab", wrote: "kaam") == nil)
        #expect(LearnableWords.corrected(over: "thick", wrote: "theek") == nil)
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
        #expect(WordSound(of: "hhh").isSilent)
        #expect(LearnableWords.corrected(over: "hhhh", wrote: "hhh") == nil)
    }

    /// A name a Devanagari dictation left on screen, corrected by re-dictating it in romanised Hinglish.
    @Test("Learns a correction from a Devanagari selection to its romanisation")
    func learnsAcrossScripts() {
        let devanagari = "\u{0930}\u{0918}\u{0941}\u{0928}\u{093E}\u{0925}"  // रघुनाथ
        #expect(LearnableWords.corrected(over: devanagari, wrote: "Raghunath") == "Raghunath")
    }
}

@Suite("The tally of what keeps turning up")
struct SightingLedgerTests {
    @Test("Keeps a term only once it has turned up on three separate days")
    func threeDays() {
        var ledger = SightingLedger()
        #expect(ledger.record(["pgvector"], on: 1).learnt.isEmpty)
        #expect(ledger.record(["pgvector"], on: 2).learnt.isEmpty)
        #expect(ledger.record(["pgvector"], on: 3).learnt == ["pgvector"])
    }

    /// A burst of dictations over one open document is one piece of evidence, not three.
    @Test("Learns nothing from three dictations on the same day")
    func oneDayIsOneSighting() {
        var ledger = SightingLedger()
        for _ in 1...3 { #expect(ledger.record(["pgvector"], on: 7).learnt.isEmpty) }
        #expect(ledger.pendingCount == 1)
    }

    /// The spelling first seen wins, so three days cannot leave the term spelt the last way seen.
    @Test("Keeps the spelling it first saw")
    func keepsTheFirstSpelling() {
        var ledger = SightingLedger()
        _ = ledger.record(["PgVector"], on: 1)
        _ = ledger.record(["pgvector"], on: 2)
        #expect(ledger.record(["PGVECTOR"], on: 3).learnt == ["PgVector"])
    }

    /// A term just learnt must leave the tally, or the next sighting learns it twice.
    @Test("Forgets a term the moment it is kept")
    func stopsCountingWhatItKept() {
        var ledger = SightingLedger()
        for day in 1...3 { _ = ledger.record(["pgvector"], on: day) }
        #expect(ledger.record(["pgvector"], on: 4).learnt.isEmpty)
        #expect(ledger.pendingCount == 1)
    }

    @Test("Counts each term on its own")
    func countsSeparately() {
        var ledger = SightingLedger()
        _ = ledger.record(["pgvector", "Valkey"], on: 1)
        _ = ledger.record(["pgvector"], on: 2)
        #expect(ledger.record(["pgvector", "Valkey"], on: 3).learnt == ["pgvector"])
    }

    /// The rows written are what a relaunch reads back, so two days on disk plus one more learns.
    @Test("Carries the tally across a relaunch through its rows")
    func survivesARelaunch() {
        var first = SightingLedger()
        let rows = first.record(["pgvector"], on: 1).rows + first.record(["pgvector"], on: 2).rows
        var second = SightingLedger(remembering: rows)
        #expect(second.record(["pgvector"], on: 3).learnt == ["pgvector"])
    }

    /// Learning cancels the term's rows, so a relaunch does not count it again from the old days.
    @Test("Cancels a learnt term's rows")
    func learningCancelsItsRows() {
        var ledger = SightingLedger()
        var rows: [UttrflowCore.EvidenceRow] = []
        for day in 1...3 { rows += ledger.record(["pgvector"], on: day).rows }
        #expect(SightingLedger(remembering: rows).pendingCount == 0)
    }

    @Test("Writes only the keyed hash, never the term")
    func rowsCarryNoText() {
        var ledger = SightingLedger(digest: { "h\($0.count)" })
        let rows = ledger.record(["pgvector"], on: 1).rows
        #expect(rows.map(\.subject) == ["h8"])
    }

    @Test("Counts nothing it cannot hash")
    func noKeyNoCount() {
        var ledger = SightingLedger(digest: { _ in nil })
        #expect(ledger.record(["pgvector"], on: 1).rows.isEmpty)
        #expect(ledger.pendingCount == 0)
    }

    /// Half-counted evidence is the app's inference about the user, and the reset throws it away too.
    @Test("Throws the whole tally away when asked, cancelling every row")
    func forgetsEverything() {
        var ledger = SightingLedger()
        var rows = ledger.record(["pgvector"], on: 1).rows
        rows += ledger.record(["pgvector"], on: 2).rows
        rows += ledger.forgetEverything()
        #expect(ledger.record(["pgvector"], on: 3).learnt.isEmpty)
        #expect(SightingLedger(remembering: rows).pendingCount == 0)
    }

    /// A tally that grew with everything glanced at would be a leak made of window titles.
    @Test("Stays inside its bound, dropping the weakest evidence first")
    func prunesToTheBound() {
        var ledger = SightingLedger()
        _ = ledger.record(["Uttrflow"], on: 1)
        _ = ledger.record(["Uttrflow"], on: 2)
        _ = ledger.record((1...SightingLedger.maximumPending * 2).map { "Term\($0)word" }, on: 2)

        // The term seen on two days survived the cull, so one more day is enough.
        #expect(ledger.pendingCount == SightingLedger.maximumPending)
        #expect(ledger.record(["Uttrflow"], on: 3).learnt == ["Uttrflow"])
    }

    @Test("Holds no more refusals than its bound, lapsing the oldest first")
    func refusalsStayInsideTheBound() {
        var ledger = SightingLedger()
        for index in 0...SightingLedger.maximumRefused { _ = ledger.refuse("Refused\(index)word") }
        #expect(ledger.refusalCount == SightingLedger.maximumRefused)

        // The first refusal lapsed, so that word counts again; the newest is still refused.
        let both = ["Refused0word", "Refused\(SightingLedger.maximumRefused)word"]
        for day in 1...2 { _ = ledger.record(both, on: day) }
        #expect(ledger.record(both, on: 3).learnt == ["Refused0word"])
    }

    @Test("Counts a word refused twice as one refusal")
    func refusingTwiceHoldsOne() {
        var ledger = SightingLedger()
        _ = ledger.refuse("pgvector")
        _ = ledger.refuse("PGVector")
        #expect(ledger.refusalCount == 1)
    }

    @Test("Restores written-down refusals inside the same bound, keeping the newest")
    func restoredRefusalsStayInsideTheBound() {
        let written = (0...SightingLedger.maximumRefused).map { "refused\($0)word" }
        let ledger = SightingLedger(refusing: written)
        #expect(ledger.refusalCount == SightingLedger.maximumRefused)
        #expect(ledger.refusals == Array(written.dropFirst()))
    }
}

@Suite("Digits inside a learnable word")
struct DigitBearingWordTests {
    @Test("Keeps a digit as part of the word it sits in")
    func keepsDigits() {
        #expect(
            LearnableWords.words(in: "GPT4 iOS17, Web3 PROJ-123", atMost: 8) == [
                "GPT4", "iOS17", "Web3", "PROJ", "123",
            ])
    }

    @Test("Learns a correction to a digit-bearing spelling whole")
    func correctionKeepsDigits() {
        #expect(LearnableWords.corrected(over: "gpt", wrote: "GPT4") == "GPT4")
    }

    @Test("Rejects digits attached to a spoken title word")
    func titleTermRejectsAttachedDigits() {
        for (title, heard) in [
            ("pgvector2 notes", "ask about pgvector"),
            ("Spreadsheet1.xlsx", "the spreadsheet is ready"),
            ("IMG_4821.HEIC", "the image is too dark"),
        ] {
            #expect(LearnableWords.seenAndSaid(heard: heard, seeing: .fixture(documentName: title)).isEmpty)
        }
    }
}
