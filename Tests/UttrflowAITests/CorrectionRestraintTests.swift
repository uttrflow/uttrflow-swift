import Testing

@testable import UttrflowAI

/// The held-back set: sentences that are already right.
///
/// This is the test the feature is for. Every sentence below is correct as it stands and
/// full of the sort of word that tempts a correction engine — real technical vocabulary,
/// real names, and ordinary English that happens to sound exactly like something in the
/// user's dictionary. The recogniser is made to doubt every word of every one of them, so
/// condition one never saves us and condition two frequently fires.
///
/// **The passing score is zero changes.** Not "few", not "mostly harmless". A dictation
/// tool that rewrites good sentences is worse than one that corrects nothing, and this
/// suite is the only thing standing between the two.
@Suite("Correction restraint")
struct CorrectionRestraintTests {
    private let engine = WordCorrectionEngine()

    /// Correct sentences, each carrying at least one word a general model would not
    /// expect. The collisions with the fixture dictionary are on purpose: "clawed" against
    /// `Claude`, "sonnet" against `Sonnet`, "kestrel" against `Kestrel`, "maven" against
    /// `Maven`, "quay" against a name, and so on.
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

    /// The same corpus, dictated into a document that already contains it — the ordinary
    /// case of correcting a draft you are looking at. Every heard word now has the
    /// on-screen signal too, and the arithmetic has to cancel rather than compound.
    @Test("changes nothing when the correct sentence is on screen", arguments: alreadyCorrect)
    func leavesCorrectSentencesAloneOnScreen(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showing(sentence))
        #expect(proposals.isEmpty, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// The hostile case, and the one a margin of one would fail. Every word of the
    /// dictionary is on the screen, so every candidate the index offers has the strongest
    /// signal there is behind it. The sentences are still right, and still must not move.
    @Test(
        "changes nothing even with the whole dictionary on screen", arguments: alreadyCorrect)
    func leavesCorrectSentencesAloneAgainstAHostileScreen(sentence: String) {
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(sentence),
            against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showingEverything)
        #expect(proposals.isEmpty, "\(sentence) → \(proposals.map(\.replacement))")
    }

    /// Guards the corpus itself.
    ///
    /// Zero changes is only an achievement if the engine was tempted. If a future edit to
    /// the fixture dictionary or to the phonetics quietly stopped these sentences matching
    /// anything, the three tests above would still pass and would be measuring nothing.
    /// This asserts that condition two — a dictionary entry sounds like something in the
    /// sentence — fires on at least fifteen of them, so their silence is restraint rather
    /// than coincidence. Seventeen do today: "clawed" and "clod" both find `Claude`,
    /// "sickle" finds `SQL`, "nickel" finds `Nikhil`, "smell" finds `XML`, "readies" finds
    /// `Redis`, "griffin" finds `Grafana`, and the two-word run "air well" finds `URL`.
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
