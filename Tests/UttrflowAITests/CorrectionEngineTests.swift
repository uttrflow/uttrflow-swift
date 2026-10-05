import Foundation
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

    @Test("eligible confidence changes do not change the independent evidence margin")
    func eligibleConfidenceDoesNotScaleTheMargin() throws {
        let heard = "we should run the ?s ?q ?l migration tonight before the release goes out to everyone"
        let evidence = CorrectionFixtures.showing("SQL migration")
        let nearlyCertain = CorrectionFixtures.spoken(heard, unsure: 0.49)
        let veryUncertain = CorrectionFixtures.spoken(heard, unsure: 0.05)

        let nearlyCertainProposal = try #require(
            engine.proposals(for: nearlyCertain, against: index, seeing: evidence).only)
        let veryUncertainProposal = try #require(
            engine.proposals(for: veryUncertain, against: index, seeing: evidence).only)

        #expect(nearlyCertainProposal.replacement == "SQL")
        #expect(veryUncertainProposal.replacement == "SQL")
        #expect(nearlyCertainProposal.reason == veryUncertainProposal.reason)
        #expect(nearlyCertainProposal.heardConfidence == 0.49)
        #expect(veryUncertainProposal.heardConfidence == 0.05)
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

    @Test("one three-word dictionary proposal fits under a fifteen-word budget")
    func multiwordProposalCountsOnceAgainstTheCap() throws {
        let utterance = CorrectionFixtures.spoken(
            "we should run the ?s ?q ?l migration tonight before the release goes out")
        #expect(utterance.words.count == 15)
        let only = try #require(engine.proposals(for: utterance, against: index).only)
        #expect(only.replacement == "SQL")
        #expect(only.wordRange.count == 3)
    }

    @Test("two distinct proposals still exceed the one-in-five budget")
    func distinctProposalsRespectTheCap() {
        let utterance = CorrectionFixtures.spoken(
            "?s ?q ?l and ?x ?m ?l")
        #expect(utterance.words.count == 7)
        #expect(engine.proposals(for: utterance, against: index).isEmpty)
    }

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

    /// Forty words with ten one-change runs; however many pieces carry them, the dictation's cap of eight holds.
    @Test(
        "the budget belongs to the dictation, so cutting it into pieces never raises it",
        arguments: [1, 2, 5, 10])
    func budgetIsTheDictations(pieces: Int) {
        let words = Array(repeating: "?s ?q ?l now", count: 10).joined(separator: " ")
            .split(separator: " ").map(String.init)
        #expect(words.count == 40)
        let size = words.count / pieces
        var budget = CorrectionBudget()
        var changed = 0
        for start in stride(from: 0, to: words.count, by: size) {
            let piece = CorrectionFixtures.spoken(words[start..<(start + size)].joined(separator: " "))
            changed +=
                engine.verdict(
                    for: piece, against: index, spending: &budget, hearing: piece.words.count
                ).proposals.count
        }
        #expect(changed <= WordCorrectionEngine.budget(for: 40))
        #expect(changed == budget.changesMade)
    }

    /// The seam pass hears no new words, so it may spend only what the pieces left.
    @Test("a pass over words already heard spends only what is left")
    func seamPassSpendsWhatIsLeft() {
        let utterance = CorrectionFixtures.spoken("the ?s ?q ?l notes are now")
        var budget = CorrectionBudget()
        #expect(
            engine.verdict(for: utterance, against: index, spending: &budget, hearing: 7).proposals.count == 1
        )
        #expect(
            engine.verdict(for: utterance, against: index, spending: &budget, hearing: 0).proposals.isEmpty)
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

    @Test("does not replace a spoken phrase with a name that only shares its opening")
    func refusesMadisonForMadSon() {
        let madison = DictionaryEntry(word: "Madison", origin: .added, firstSeen: .now)
        let proposals = WordCorrectionEngine().proposals(
            for: CorrectionFixtures.spoken("we should tell the ?mad ?son of the king about it tomorrow"),
            against: PhoneticIndex(entries: [madison]),
            seeing: CorrectionFixtures.showing("Madison marketing plan"))

        #expect(proposals.isEmpty)
    }

    @Test("corrects a spoken Kubernetes pronunciation when the entry says it sounds that way")
    func correctsKubernetesPronunciation() throws {
        let kubernetes = DictionaryEntry(
            word: "Kubernetes", pronunciation: "kuber netes", origin: .added, firstSeen: .now)
        let proposals = WordCorrectionEngine().proposals(
            for: CorrectionFixtures.spoken("we should restart the ?kuber ?netes pod after the deploy"),
            against: PhoneticIndex(entries: [kubernetes]),
            seeing: CorrectionFixtures.showing("Kubernetes deployment"))

        #expect(try #require(proposals.only).replacement == "Kubernetes")
    }

    @Test(
        "refuses an entry that neither spells a multi-word run nor writes out its pronunciation",
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
        "keeps a run the entry writes out",
        arguments: [
            ("PaymentSheet", "payment sheet"), ("setUserPrefs", "set user prefs"),
            ("SQL", "s q l"), ("Grafana", "graf an a"),
        ])
    func keepsARunItSpells(entry: String, heard: String) {
        #expect(
            WordCorrectionEngine.spells(
                DictionaryEntry(word: entry, origin: .added, firstSeen: .now), asHeard: heard))
    }

    @Test(
        "keeps a run the entry reads as when closed up",
        arguments: [
            ("Uttrflow", "utter flow"), ("Kubelet", "cube lit"), ("Zorvath", "zore vath"),
            ("Priyanka", "pre yanka"), ("SQLite", "sequel lite"),
        ])
    func keepsARunItReadsAs(entry: String, heard: String) {
        #expect(
            WordCorrectionEngine.spells(
                DictionaryEntry(word: entry, origin: .added, firstSeen: .now), asHeard: heard))
    }

    @Test(
        "refuses a run that sounds like neither the entry nor its letters",
        arguments: [("Gauri", "g r p c x"), ("Calloway", "post gress q l"), ("Gauri", "c r d t")])
    func refusesAnUnrelatedRun(entry: String, heard: String) {
        #expect(
            WordCorrectionEngine.spells(
                DictionaryEntry(word: entry, origin: .added, firstSeen: .now), asHeard: heard)
                == false)
    }

    @Test("corrects a run the recogniser split into words that sound like the entry")
    func correctsUtterFlow() throws {
        let uttrflow = DictionaryEntry(word: "Uttrflow", origin: .added, firstSeen: .now)
        let proposals = WordCorrectionEngine().proposals(
            for: CorrectionFixtures.spoken("I dictated this note with ?utter ?flow on my laptop today"),
            against: PhoneticIndex(entries: [uttrflow]),
            seeing: CorrectionFixtures.showing("Uttrflow settings"))

        #expect(try #require(proposals.only).replacement == "Uttrflow")
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

    // MARK: Case only

    /// An index holding only the two entries the case-only tests need.
    private static let cased = PhoneticIndex(
        entries: ["YoY", "Docker"].map {
            DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        })

    @Test(
        "writes a surely heard word in the entry's case when only the case differs",
        arguments: [
            ("Sales were up 12% YOY.", "Sales were up 12% YoY."),
            ("The docker image is too large to deploy.", "The Docker image is too large to deploy."),
        ])
    func recasesASureWord(heard: String, written: String) throws {
        let utterance = CorrectionFixtures.spoken(heard)
        let proposals = WordCorrectionEngine().proposals(for: utterance, against: Self.cased)
        let only = try #require(proposals.only)
        #expect(only.reason == .spelledAsInDictionary)
        #expect(only.heardConfidence == 0.95)
        let words = utterance.words.map(\.text)
        #expect(WordCorrection.applying(proposals, to: words).joined(separator: " ") == written)
    }

    @Test(
        "leaves the heard case alone without the entry",
        arguments: ["Sales were up 12% YOY.", "The docker image is too large to deploy."])
    func keepsTheCaseWithoutTheEntry(heard: String) {
        let utterance = CorrectionFixtures.spoken(heard)
        #expect(WordCorrectionEngine().proposals(for: utterance, against: PhoneticIndex(entries: [])).isEmpty)
    }

    @Test("never recases a near spelling, only the entry's exact letters")
    func keepsANearSpelling() {
        let utterance = CorrectionFixtures.spoken("The dockers say YOYO and dock her.")
        #expect(WordCorrectionEngine().proposals(for: utterance, against: Self.cased).isEmpty)
    }
}
