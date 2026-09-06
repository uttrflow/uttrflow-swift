import Testing

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

    @Test(
        "changes nothing in a correct sentence, however badly it was heard",
        arguments: alreadyCorrect)
    func leavesCorrectSentencesAlone(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence), against: CorrectionFixtures.index)
        #expect(proposals.isEmpty, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// The same corpus on screen: every heard word gains that signal too, so the arithmetic must cancel.
    @Test("changes nothing when the correct sentence is on screen", arguments: alreadyCorrect)
    func leavesCorrectSentencesAloneOnScreen(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showing(sentence))
        #expect(proposals.isEmpty, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// The whole dictionary on screen gives every candidate the strongest signal; a margin of one would fail.
    @Test(
        "changes nothing even with the whole dictionary on screen", arguments: alreadyCorrect)
    func leavesCorrectSentencesAloneAgainstAHostileScreen(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showingEverything)
        #expect(proposals.isEmpty, "\(sentence) → \(proposals.map(\.replacement))")
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
    }
}
