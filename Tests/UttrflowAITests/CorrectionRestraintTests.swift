import Testing
import UttrflowCore

@testable import UttrflowAI

/// Correct sentences, every word doubted; passing is zero changes. See Docs/ai-correction-thresholds.md.
@Suite("Correction restraint")
struct CorrectionRestraintTests {
    /// The engine under test.
    private let engine = WordCorrectionEngine()

    /// Correct sentences whose words collide with the fixture dictionary on purpose: "clawed", "sonnet".
    static let alreadyCorrect = [
        "The bear clawed the bark off a young tree",
        "She wrote a sonnet about the harbour at dawn",
        "A kestrel hovered above the motorway verge",
        "Cassandra warned them and nobody listened",
        "The maven of modern architecture spoke first",
        "Idempotent retries prevent duplicate charges",
        "The mitochondrion supplies the cell with energy",
        "Bougainvillea covered the whole veranda",
        "The anemometer recorded a forty knot gust",
        "Chiaroscuro defines the mood of the painting",
        "Siobhan and Xiaoming presented the findings",
        "The paediatrician recommended a second opinion",
        "Hyperbolic discounting explains the whole quarter",
        "The chancellor rebuffed the amendment twice",
        "Quinoa and freekeh are both ancient grains",
        "The barista tamped the espresso puck evenly",
        "Nikhil reviewed the pull request this morning",
        "Terraform planned nineteen resources to add",
        "He moored the sloop against the old quay",
        "Anodised aluminium resists the salt air well",
        "The cloud thickened over the estuary",
        "A rusty sickle hung in the old barn",
        "The nickel plating had begun to flake",
        "That smell of creosote lingers for days",
        "She readies the boat before the tide turns",
        "He looked up the ledger before signing",
        "A griffin guarded the gate in the fresco",
        "The clod of earth broke apart in his hand",
    ]

    /// The same temptations at a length where the blast-radius cap allows two changes, not one.
    static let alreadyCorrectAtLength = [
        "Anodised aluminium resists the salt air well enough for the coast in winter",
        "The bear clawed the bark off a young tree beside the river last spring",
        "She wrote a sonnet about the harbour at dawn and read it to nobody",
        "The maven of modern architecture spoke first and the room went quiet afterwards",
        "He moored the sloop against the old quay before the weather turned that evening",
        "A kestrel hovered above the motorway verge for a while and then dropped away",
        "The paediatrician recommended a second opinion before we agreed to anything at all",
        "Idempotent retries prevent duplicate charges when the network drops midway through a payment",
    ]

    @Test(
        "changes nothing in a correct sentence, however badly it was heard",
        arguments: alreadyCorrect)
    func leavesCorrectSentencesAlone(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence), against: CorrectionFixtures.index)
        #expect(proposals.allSatisfy { $0.isRecasing }, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// The same corpus on screen: every heard word gains that signal too, so the arithmetic must cancel.
    @Test("changes nothing when the correct sentence is on screen", arguments: alreadyCorrect)
    func leavesCorrectSentencesAloneOnScreen(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showing(sentence))
        #expect(proposals.allSatisfy { $0.isRecasing }, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// The whole dictionary on screen gives every candidate the strongest signal; a margin of one would fail.
    @Test(
        "changes nothing even with the whole dictionary on screen", arguments: alreadyCorrect)
    func leavesCorrectSentencesAloneAgainstAHostileScreen(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showingEverything)
        #expect(proposals.allSatisfy { $0.isRecasing }, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// The evidence margin, not the blast-radius cap: at this length the cap allows the change.
    @Test(
        "changes nothing in a longer correct sentence, with the whole dictionary on screen",
        arguments: alreadyCorrectAtLength)
    func leavesLongerSentencesAlone(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showingEverything)
        #expect(proposals.allSatisfy { $0.isRecasing }, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// Without this the test above measures the cap again, which the short corpus already measures.
    @Test("the longer sentences really do allow more than one change")
    func longerSentencesHaveABudgetAboveOne() {
        for sentence in Self.alreadyCorrectAtLength {
            let words = CorrectionFixtures.doubting(sentence).words.count
            #expect(
                WordCorrectionEngine.budget(for: words) >= 2,
                "\(sentence) is \(words) words, so the cap still allows only one change")
        }
    }

    /// The application in front is not evidence for a spelling, which is the learner's rule too.
    @Test("does not take the application's own name as a sighting")
    func theApplicationNameIsNotEvidence() {
        let sentence = "Anodised aluminium resists the salt air well enough for the coast in winter"
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: AppContext(applicationName: CorrectionFixtures.words.joined(separator: " ")))
        #expect(proposals.allSatisfy { $0.isRecasing }, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// Every run the gate had a reading for and declined is named, so a later layer cannot reopen it.
    @Test("holds each tempting run it declines, and only those", arguments: alreadyCorrect)
    func holdsWhatItDeclines(sentence: String) {
        let utterance = CorrectionFixtures.doubting(sentence)
        let verdict = engine.verdict(for: utterance, against: CorrectionFixtures.index)
        let tempting = UncertainSpan.spans(in: utterance, below: WordCorrectionEngine.certaintyThreshold)
            .filter { span in
                WordCorrectionEngine.spellings(of: span.text, in: CorrectionFixtures.index)
                    .contains { WordCorrectionEngine.spells($0.entry, asHeard: $0.heard) }
            }
        let changed = Set(verdict.proposals.flatMap(\.wordRange))
        let held = Set(verdict.held.flatMap { $0 })
        #expect(held == Set(tempting.flatMap(\.range)).subtracting(changed), "\(sentence)")
    }

    /// Fifteen sentences must tempt the dictionary, or the three tests above measure nothing.
    @Test("the held-back sentences really do tempt the dictionary")
    func corpusIsTempting() {
        let tempted = Self.alreadyCorrect.filter { sentence in
            UncertainSpan.spans(
                in: CorrectionFixtures.doubting(sentence),
                below: WordCorrectionEngine.certaintyThreshold
            )
            .contains { !CorrectionFixtures.index.candidates(soundingLike: $0.text).isEmpty }
        }
        #expect(
            tempted.count >= 15,
            "only \(tempted.count) of \(Self.alreadyCorrect.count) sentences match anything")
        // Pinned so Docs/ai-correction-thresholds.md's exact count is caught, not left to drift.
        #expect(
            tempted.count == 16,
            "Docs/ai-correction-thresholds.md says 16 sentences tempt the dictionary; update it too")
    }
}

extension WordCorrection {
    /// Whether this only writes the heard letters in a dictionary entry's case, which restraint allows.
    fileprivate var isRecasing: Bool {
        reason == .spelledAsInDictionary && replacement.lowercased() == heard.lowercased()
    }
}
