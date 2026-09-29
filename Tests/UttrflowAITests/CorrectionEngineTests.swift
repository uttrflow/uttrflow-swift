import UttrflowCore
import UttrflowDictionary
import Testing

@testable import UttrflowAI

/// The engine works when all three conditions hold, and each condition alone stops it.
@Suite("WordCorrectionEngine")
struct CorrectionEngineTests {
    /// The engine under test.
    private let engine = WordCorrectionEngine()
    /// The shared fixture dictionary.
    private let index = CorrectionFixtures.index

    /// Fifteen words buys a budget of three, exactly one three-word run, so the cap is not what is tested.
    private static let migration =
        "we should run the ?s ?q ?l migration tonight before the release goes out to everyone"

    // MARK: All three conditions

    @Test("replaces a word the recogniser spelt out rather than heard")
    func correctsStrayLetters() throws {
        let proposals = engine.proposals(for: CorrectionFixtures.spoken(Self.migration), against: index)
        let only = try #require(proposals.only)
        #expect(only.heard == "s q l")
        #expect(only.replacement == "SQL")
        #expect(only.wordRange == 4..<7)
        #expect(only.reason == .heardAsStrayLetters)
        #expect(only.heardConfidence == 0.2)
    }

    /// The flagship case: "payment sheet" with `PaymentSheet.swift` open in front of the speaker.
    @Test("joins two spoken words into the one written word on screen")
    func correctsAgainstTheScreen() throws {
        let utterance = CorrectionFixtures.spoken(
            "I moved the ?payment ?sheet into its own file this afternoon and pushed it")
        let proposals = engine.proposals(
            for: utterance, against: index, seeing: CorrectionFixtures.showing("PaymentSheet.swift"))
        let only = try #require(proposals.only)
        #expect(only.heard == "payment sheet")
        #expect(only.replacement == "PaymentSheet")
        #expect(only.reason == .seenOnScreen)
    }

    /// The clear hearing makes the fumbled one safe to fix, because doubted words never corroborate.
    @Test("repairs a word the same dictation already got right")
    func correctsAgainstAnEarlierHearing() throws {
        let utterance = CorrectionFixtures.spoken(
            "Uttrflow works offline and the whole point of ?utter ?flow is that nothing leaves the Mac")
        let only = try #require(engine.proposals(for: utterance, against: index).only)
        #expect(only.heard == "utter flow")
        #expect(only.replacement == "Uttrflow")
        #expect(only.reason == .saidClearlyElsewhere)
    }

    // MARK: Each condition, failed on its own

    /// Condition one. Everything else about this utterance is identical to the one above.
    @Test("condition one alone: a confident hearing is never touched")
    func confidenceBlocksTheCorrection() {
        let utterance = CorrectionFixtures.spoken(
            "we should run the s q l migration tonight before the release goes out to everyone")
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// A word the recogniser was sure of stays even when the dictionary and the screen both hold it.
    @Test("a confident word survives a perfect dictionary match")
    func confidentWordSurvivesAPerfectMatch() {
        let utterance = CorrectionFixtures.spoken("please deploy postgres and redis this evening")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showingEverything
            ).isEmpty)
    }

    /// And a run may not be replaced wholesale to get at the doubtful half of it.
    @Test("a run containing one confident word is not replaced")
    func confidentWordProtectsTheRunAroundIt() {
        let utterance = CorrectionFixtures.spoken(
            "I moved the payment ?sheet into its own file this afternoon and pushed it")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showing("PaymentSheet.swift")
            ).isEmpty)
    }

    /// Condition two: unsure and corroborated, but nothing in the dictionary sounds like it.
    @Test("condition two alone: no candidate, no correction")
    func absentCandidateBlocksTheCorrection() {
        let utterance = CorrectionFixtures.spoken(
            "we should run the ?zzt ?wug ?blint migration tonight before the release goes out")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showingEverything
            ).isEmpty)
    }

    /// Condition three: everything in place except a reason to believe the candidate belongs here.
    @Test("condition three alone: an uncorroborated candidate is left alone")
    func absentEvidenceBlocksTheCorrection() {
        let utterance = CorrectionFixtures.spoken(
            "I moved the ?payment ?sheet into its own file this afternoon and pushed it")
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// The case a margin of one gets wrong: a real word, heard as itself, with a homophone on screen.
    @Test("one signal is not enough to overrule a word of the same shape")
    func oneSignalIsNotEnough() {
        let utterance = CorrectionFixtures.spoken(
            "the bear ?clawed the bark off a young tree beside the river this morning")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showing("Claude notes")
            ).isEmpty)
    }

    /// An entry spelling what was heard silences its homophones, `Sonnet` and `Cassandra` included.
    @Test("an entry that spells what was heard silences its own homophones")
    func anExactEntryVouchesForTheHearing() {
        let utterance = CorrectionFixtures.spoken(
            "?Cassandra warned them and nobody listened to a word of it before the launch")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showingEverything
            ).isEmpty)
    }

    // MARK: The one-in-five cap

    /// Four stray-letter runs in twenty-two words want twelve changes where four are allowed.
    @Test("abandons the whole utterance rather than change more than one word in five")
    func capAbandonsAnOverEagerUtterance() {
        let utterance = CorrectionFixtures.spoken(
            "the ?s ?q ?l and ?a ?p ?i and ?x ?m ?l and ?c ?s ?s notes are all in the folder")
        #expect(utterance.words.count == 22)
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// The same utterance with three runs heard properly, proving the cap is what stops the one above.
    @Test("the same utterance with one run left in it is corrected")
    func capAllowsWhatFitsInsideIt() throws {
        let utterance = CorrectionFixtures.spoken(
            "the ?s ?q ?l and json and yaml and toml and csv and text and env notes are all in the folder"
        )
        #expect(utterance.words.count == 22)
        let only = try #require(engine.proposals(for: utterance, against: index).only)
        #expect(only.replacement == "SQL")
    }

    @Test(
        "the budget is one word in five, and never zero",
        arguments: [(0, 1), (1, 1), (4, 1), (5, 1), (9, 1), (10, 2), (25, 5)])
    func budgetIsOneInFive(words: Int, allowed: Int) {
        #expect(WordCorrectionEngine.budget(for: words) == allowed)
    }

    // MARK: What it costs

    /// Counted rather than timed, so load cannot fail it. See Docs/ai-correction-thresholds.md.
    @Test("correcting a whole dictation reads the screen once and no more of a larger dictionary")
    func costsAlmostNothing() {
        func dictionary(_ size: Int) -> PhoneticIndex {
            PhoneticIndex(
                entries: (0..<size).map { number in
                    // Spelt in `B`, `V` and vowels, so every filler word has a sound of its own and none is heard.
                    let spelling = (0..<16).map { (number >> $0) & 1 == 0 ? "ba" : "va" }.joined()
                    return DictionaryEntry(word: spelling, origin: .observed, firstSeen: .distantPast)
                } + CorrectionFixtures.entries)
        }
        let utterance = CorrectionFixtures.spoken(
            """
            we should run the ?s ?q ?l migration tonight before the ?payment ?sheet work lands \
            and then ?utter ?flow can go out on Friday with the ?x ?m ?l importer and the rest of \
            the release notes we drafted
            """)
        let context = CorrectionFixtures.showing(
            String(repeating: "PaymentSheet swift ", count: 250))

        func work(over index: PhoneticIndex) -> (proposals: [WordCorrection], entries: Int, screens: Int) {
            let entries = WorkTally()
            let screens = WorkTally()
            let proposals = PhoneticIndex.$entriesRead.withValue(entries) {
                CorrectionEvidence.$screensRead.withValue(screens) {
                    engine.proposals(for: utterance, against: index, seeing: context)
                }
            }
            return (proposals, entries.count, screens.count)
        }

        let small = work(over: dictionary(50))
        let large = work(over: dictionary(10_000))
        print("CORRECTION  entries read over 50: \(small.entries), over 10,000: \(large.entries)")

        #expect(small.entries > 0, "the doubted runs found candidates, so reading was counted")
        #expect(large.proposals == small.proposals)
        #expect(large.entries == small.entries, "a larger dictionary costs no more entries read")
        #expect(large.screens == 1, "the screen is read once per utterance, not once per doubted run")
    }

    // MARK: Housekeeping

    @Test("an empty utterance is nothing to correct")
    func emptyUtteranceIsLeftAlone() {
        #expect(engine.proposals(for: CorrectionFixtures.spoken(""), against: index).isEmpty)
    }

    /// An empty dictionary can never satisfy condition two, whatever else is true.
    @Test("an empty dictionary proposes nothing")
    func emptyDictionaryProposesNothing() {
        #expect(
            engine.proposals(
                for: CorrectionFixtures.spoken(Self.migration), against: PhoneticIndexFixture.empty
            ).isEmpty)
    }

    /// Two runs can want the same words, "s q l" and "q l", and only one answer is given.
    @Test("overlapping proposals are resolved to one")
    func overlappingProposalsAreResolved() throws {
        let proposals = engine.proposals(for: CorrectionFixtures.spoken(Self.migration), against: index)
        #expect(proposals.count == 1)
        let only = try #require(proposals.only)
        #expect(only.wordRange.count == 3)
    }

    @Test("proposals come back in the order the words were spoken")
    func proposalsAreInSpokenOrder() {
        let utterance = CorrectionFixtures.spoken(
            """
            the ?s ?q ?l file and the ?x ?m ?l file are both in the repository somewhere \
            near the top of it which I will check again tomorrow morning before the standup
            """)
        let proposals = engine.proposals(for: utterance, against: index)
        #expect(proposals.map(\.replacement) == ["SQL", "XML"])
        #expect(proposals.map(\.wordRange.lowerBound) == [1, 7])
    }
}

/// Named indexes the engine tests need that the shared fixture has no business holding.
enum PhoneticIndexFixture {
    /// An index with no entries.
    static let empty = PhoneticIndex(entries: [])
}

extension Array {
    /// The single element, or nil otherwise; `first` would pass a test that produced three corrections.
    fileprivate var only: Element? { count == 1 ? first : nil }
}

/// Which runs of several words an entry may take, which the evidence margin does not answer.
@Suite("A run of several words")
struct MultiWordCorrectionTests {
    // MARK: - A run of several words

    /// Measured on this corpus: two signals clear the margin, and at length nothing else stopped them.
    @Test(
        "refuses an entry that neither spells a multi-word run nor opens as it does",
        arguments: [
            ("URL", "air well"), ("Aditi", "it to"),
        ])
    func refusesARunItDoesNotSpell(entry: String, heard: String) {
        #expect(
            WordCorrectionEngine.spells(
                DictionaryEntry(word: entry, origin: .added, firstSeen: .now), asHeard: heard)
                == false)
    }

    @Test(
        "keeps a run the entry spells, or opens as",
        arguments: [
            ("PaymentSheet", "payment sheet"), ("setUserPrefs", "set user prefs"),
            ("Uttrflow", "utter flow"), ("SQL", "s q l"), ("Grafana", "graf an a"),
        ])
    func keepsARunItSpells(entry: String, heard: String) {
        #expect(
            WordCorrectionEngine.spells(
                DictionaryEntry(word: entry, origin: .added, firstSeen: .now), asHeard: heard))
    }

    /// A shared sound key cannot make two unrelated spellings plausible readings.
    @Test("refuses a single-word phonetic collision that does not open alike")
    func refusesAnUnrelatedSingleWordReading() {
        let colin = DictionaryEntry(word: "Colin", origin: .added, firstSeen: .now)
        #expect(PhoneticIndex(entries: [colin]).candidates(soundingLike: "Kaelin").contains(colin))
        #expect(!ReadingRestraint.opensAlike(colin.word, heard: "Kaelin"))
        #expect(WordCorrectionEngine.spells(colin, asHeard: "Kaelin") == false)
    }

    @Test(
        "keeps a single-word spelling that is exact or opens alike",
        arguments: [("Colin", "Colin"), ("Cache", "cash")])
    func keepsAResemblingSingleWordReading(entry: String, heard: String) {
        #expect(
            WordCorrectionEngine.spells(
                DictionaryEntry(word: entry, origin: .added, firstSeen: .now), asHeard: heard))
    }

    /// The pronunciation field exists for exactly this: a spelling that does not open as the sound does.
    @Test("takes the run back when the user wrote the pronunciation for it")
    func thePronunciationCounts() {
        let bare = DictionaryEntry(word: "Kubectl", origin: .added, firstSeen: .now)
        let said = DictionaryEntry(
            word: "Kubectl", pronunciation: "cube cuttle", origin: .added, firstSeen: .now)

        #expect(WordCorrectionEngine.spells(bare, asHeard: "cube cuttle") == false)
        #expect(WordCorrectionEngine.spells(said, asHeard: "cube cuttle"))
    }
}
