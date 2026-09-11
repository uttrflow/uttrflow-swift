import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// Regression for issue 217: a screen word that only collides on a sound key is no reading. See `Docs/cleanup.md`.
@Suite("Issue 217: an ordinary screen word is no reading of an ordinary spoken word")
struct Issue217ReadingRestraintTests {
    private let source = ScreenCandidates()

    /// The encoder is lossy on purpose, which is why every caller has to restrain it rather than trust it.
    @Test("the sound keys still collide, which is what makes the restraint necessary")
    func codesStillCollide() {
        let made = DoubleMetaphone.code(for: "made")
        for word in ["mid", "mod", "mad", "mood", "mud"] {
            #expect(DoubleMetaphone.code(for: word) == made)
        }
        #expect(DoubleMetaphone.code(for: "bot").sounds(like: DoubleMetaphone.code(for: "but")))
        #expect(DoubleMetaphone.code(for: "main").sounds(like: DoubleMetaphone.code(for: "mean")))
    }

    @Test("refuses the screen's 'mod' as a reading of the spoken 'made'")
    func refusesModForMade() async {
        let found = await source.candidates(
            for: Draft.Word("made", confidence: 0.42),
            in: .showing(title: "parser.rs", preceding: "pub mod parser;\nlet x = "))
        #expect(!found.contains("mod"))
    }

    @Test("refuses 'bot' for 'but' and 'main' for 'mean', which open differently too")
    func refusesTheOtherCollisions() async {
        let bot = await source.candidates(
            for: Draft.Word("but", confidence: 0.42), in: .showing(title: "bot.py"))
        let main = await source.candidates(
            for: Draft.Word("mean", confidence: 0.42), in: .showing(title: "main.go"))
        #expect(!bot.contains("bot"))
        #expect(!main.contains("main"))
    }

    /// The asymmetry the issue was: one source refused this reading and its sibling offered it.
    @Test("answers what the ordinary-words source answers for the same word")
    func agreesWithTheSibling() async {
        let screen = await source.candidates(
            for: Draft.Word("made", confidence: 0.42),
            in: .showing(title: "parser.rs", preceding: "pub mod parser;"))
        let phonetic = await PhoneticCandidates().candidates(
            for: Draft.Word("made", confidence: 0.42), in: .showing(title: "parser.rs"))
        #expect(screen.isEmpty)
        #expect(phonetic.isEmpty)
    }

    @Test("offers no span, so the collision never reaches the prompt line")
    func reachesNoPromptLine() async {
        let spans = await DoubtfulWords.standard.spans(
            in: .heard("i ?made a change to the parser", unsure: 0.42),
            for: .showing(title: "parser.rs", preceding: "pub mod parser;\nlet x = "))
        #expect(spans.isEmpty)
        #expect(PromptBuilder.doubtfulText(spans) == nil)
    }

    /// Being offered was the whole gate, so with nothing offered the guard is what refuses the substitution.
    @Test("the guard refuses the substitution the prompt no longer makes available")
    func guardRefusesIt() async {
        let spans = await DoubtfulWords.standard.spans(
            in: .heard("i ?made a change to the parser", unsure: 0.42),
            for: .showing(title: "parser.rs", preceding: "pub mod parser;\nlet x = "))
        let verdict = MeaningPreservationGuard().verdict(
            draft: .heard("i ?made a change to the parser", unsure: 0.42),
            rewritten: "I mod a change to the parser.", offering: spans)
        #expect(verdict == .rejected(reason: "the rewrite lost or replaced 'made'"))
    }

    @Test("still offers the reading that sounds alike and opens alike")
    func keepsTheRealReading() async {
        let found = await source.candidates(
            for: Draft.Word("cash", confidence: 0.42), in: .showing(title: "Cache.swift"))
        #expect(found == ["Cache"])
    }
}
