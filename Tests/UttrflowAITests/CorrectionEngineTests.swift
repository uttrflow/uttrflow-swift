import UttrflowDictionary
import Testing

@testable import UttrflowAI

/// The other half of the bargain: the engine has to work when all three conditions hold,
/// and each condition has to be the thing that stops it when it does not.
@Suite("WordCorrectionEngine")
struct CorrectionEngineTests {
    private let engine = WordCorrectionEngine()
    private let index = CorrectionFixtures.index

    /// Long enough that the one-in-five cap is not what is being tested — fifteen words
    /// buys a budget of three, which is exactly one three-word run.
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

    /// The flagship case: nobody dictates `PaymentSheet` as one word, and the file it lives
    /// in is open in front of them while they say it.
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

    /// The same word, said clearly once and fumbled once. The clear hearing is what makes
    /// the fumbled one safe to fix — and it can only do that because a word below the
    /// certainty line is never allowed to corroborate anything, itself included.
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

    /// The hard stop stated in its own terms: a word the recogniser was sure of stays, even
    /// when the dictionary holds that exact word and the screen is showing it.
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

    /// Condition two. The recogniser is unsure and the screen corroborates, but no entry in
    /// the dictionary sounds like what was heard, so there is nothing to offer.
    @Test("condition two alone: no candidate, no correction")
    func absentCandidateBlocksTheCorrection() {
        let utterance = CorrectionFixtures.spoken(
            "we should run the ?zzt ?wug ?blint migration tonight before the release goes out")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showingEverything
            ).isEmpty)
    }

    /// Condition three, which is the whole restraint. Everything is in place except a
    /// reason to believe the candidate belongs in this particular sentence.
    @Test("condition three alone: an uncorroborated candidate is left alone")
    func absentEvidenceBlocksTheCorrection() {
        let utterance = CorrectionFixtures.spoken(
            "I moved the ?payment ?sheet into its own file this afternoon and pushed it")
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// One signal is a coincidence. This is the case a margin of one would get wrong: a
    /// real English word, heard as itself, with a homophone of it open on the screen.
    @Test("one signal is not enough to overrule a word of the same shape")
    func oneSignalIsNotEnough() {
        let utterance = CorrectionFixtures.spoken(
            "the bear ?clawed the bark off a young tree beside the river this morning")
        #expect(
            engine.proposals(
                for: utterance, against: index, seeing: CorrectionFixtures.showing("Claude notes")
            ).isEmpty)
    }

    /// The dictionary spelling what was heard, exactly, is the strongest statement there is
    /// that the hearing was right — even though `Sonnet` and `Cassandra` are both entries
    /// and both sound like the words around them.
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

    /// Four stray-letter runs in twenty-two words: twelve words wanted where four are
    /// allowed. Every one of the four is a change the engine would happily make on its
    /// own, which is exactly why it must make none of them.
    @Test("abandons the whole utterance rather than change more than one word in five")
    func capAbandonsAnOverEagerUtterance() {
        let utterance = CorrectionFixtures.spoken(
            "the ?s ?q ?l and ?a ?p ?i and ?x ?m ?l and ?c ?s ?s notes are all in the folder")
        #expect(utterance.words.count == 22)
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

    /// The same utterance to the word, with three of the four runs heard properly, to show
    /// that it was the cap that stopped the one above and not some other failure.
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

    /// The latency claim, asserted rather than believed.
    ///
    /// Correction sits on the dictation path beside transcription (~0.6s) and tidying
    /// (~1.4s), and the reason condition three counts evidence instead of asking a language
    /// model is that a model call per uncertain word would be the third-largest cost in the
    /// product. Ten thousand entries, a forty-word utterance where half the words are
    /// doubted, and a screenful of selected text: comfortably worse than a real dictation,
    /// and it measures around half a millisecond on this Mac.
    ///
    /// The bound asserted is far above that, deliberately. A wall clock inside a suite that
    /// runs its tests in parallel is a noisy instrument, and a threshold set near the
    /// measurement would fail on a busy machine and teach everyone to ignore it. What needs
    /// defending is not half a millisecond but the *order*: twenty-five is still a hundredth
    /// of the dictation budget, and it is two orders of magnitude below what one on-device
    /// model call costs — so this fails loudly the day somebody puts one here, and never
    /// otherwise. The number it actually took is printed either way.
    @Test("correcting a whole dictation is not a measurable part of it")
    func costsAlmostNothing() {
        let big = PhoneticIndex(
            entries: (0..<10_000).map {
                DictionaryEntry(word: "coined\($0)", origin: .observed, firstSeen: .distantPast)
            } + CorrectionFixtures.entries)
        let utterance = CorrectionFixtures.spoken(
            """
            we should run the ?s ?q ?l migration tonight before the ?payment ?sheet work lands \
            and then ?utter ?flow can go out on Friday with the ?x ?m ?l importer and the rest of \
            the release notes we drafted
            """)
        let context = CorrectionFixtures.showing(
            String(repeating: "PaymentSheet swift ", count: 250))

        let repetitions = 200
        let elapsed = ContinuousClock().measure {
            for _ in 0..<repetitions {
                _ = engine.proposals(for: utterance, against: big, seeing: context)
            }
        }
        let each = elapsed / repetitions
        print("CORRECTION  \(utterance.words.count) words over 10,000 entries: \(each)")
        #expect(each < .milliseconds(25))
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

    /// Two runs can want the same words — "s q l" contains "q l" — and only one answer can
    /// be given for them.
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
    static let empty = PhoneticIndex(entries: [])
}

extension Array {
    /// The single element, or `nil` when there is not exactly one.
    ///
    /// `first` would quietly pass a test that produced three corrections where one was
    /// expected, and in this engine an extra correction is the failure.
    fileprivate var only: Element? { count == 1 ? first : nil }
}
