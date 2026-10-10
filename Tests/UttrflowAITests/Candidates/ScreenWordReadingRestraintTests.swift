import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// Regression for issue 217: a screen word that only collides on a sound key is no reading. See `Docs/cleanup.md`.
@Suite("An ordinary screen word is no reading of an ordinary spoken word", .bug(id: 217))
struct ScreenWordReadingRestraintTests {
    private let source = ScreenCandidates()

    /// The encoder is lossy on purpose, which is why every caller has to restrain it rather than trust it.
    @Test("the sound keys still collide, which is what makes the restraint necessary")
    func codesStillCollide() {
        let made = WordSound(of: "made")
        for word in ["mid", "mod", "mad", "mood", "mud"] {
            #expect(WordSound(of: word) == made)
        }
        #expect(WordSound(of: "bot").sounds(like: WordSound(of: "but")))
        #expect(WordSound(of: "main").sounds(like: WordSound(of: "mean")))
    }

    @Test("refuses 'main' for 'mean', two ordinary words not said alike")
    func refusesTheOtherCollisions() async {
        let main = await source.candidates(
            for: Draft.Word("mean", evidence: .score(0.42)), in: .showing(title: "main.go"))
        #expect(!main.contains("main"))
    }

    /// The asymmetry the issue was: one source refused this reading and its sibling offered it.
    @Test("answers what the ordinary-words source answers for the same word")
    func agreesWithTheSibling() async {
        let screen = await source.candidates(
            for: Draft.Word("made", evidence: .score(0.42)),
            in: .showing(title: "parser.rs", preceding: "pub mod parser;"))
        let phonetic = await PhoneticCandidates().candidates(
            for: Draft.Word("made", evidence: .score(0.42)), in: .showing(title: "parser.rs"))

        #expect(screen.isEmpty == phonetic.isEmpty)

    }

    /// The second rule the issue names: what is on screen is evidence only when the word is not one everybody knows.
    @Test("refuses an ordinary screen word as a reading of an ordinary spoken one")
    func vetoesTwoOrdinaryWords() async {
        let man = await source.candidates(
            for: Draft.Word("main", evidence: .score(0.42)), in: .showing(title: "man page"))
        let main = await source.candidates(
            for: Draft.Word("mean", evidence: .score(0.42)), in: .showing(title: "main.go"))
        #expect(man.isEmpty)
        #expect(main.isEmpty)
    }

    /// Both sides of each pair are ordinary words, so the veto reaches them: see the doubtful-words row of `Docs/cleanup.md`.
    @Test("refuses a collision between two ordinary words that are not listed homophones")
    func refusesAnUnlistedOrdinaryCollision() async {
        let mad = await source.candidates(
            for: Draft.Word("made", evidence: .score(0.42)), in: .showing(title: "mad.rs"))
        let men = await source.candidates(
            for: Draft.Word("mean", evidence: .score(0.42)), in: .showing(title: "men.csv"))
        #expect(mad.isEmpty)
        #expect(men.isEmpty)
    }

    @Test("still offers the reading that sounds alike and opens alike")
    func keepsTheRealReading() async {
        let found = await source.candidates(
            for: Draft.Word("cash", evidence: .score(0.42)), in: .showing(title: "Cache.swift"))
        #expect(found == ["Cache"])
    }
}
