import Testing

@testable import UttrflowPredict

@Suite("Staying quiet")
struct QuietingTests {
    @Test("An ordinary moment is not refused.")
    func ordinary() {
        #expect(Quieting.reason(PredictionContext(typed: "git c")) == nil)
    }

    @Test(
        "Each rule refuses on its own.",
        arguments: [
            (PredictionContext(typed: "x", isEnabledHere: false), Quieting.Reason.turnedOffHere),
            (PredictionContext(typed: "x", isSecure: true), .secureField),
            (PredictionContext(typed: "x", hasSelection: true), .textSelected),
            (PredictionContext(typed: "x", caretAtLineEnd: false), .caretInsideText),
            (PredictionContext(typed: "x", rejectionsThisSession: 3), .rejectedTooOften),
            (
                PredictionContext(typed: "x", isProse: true, millisecondsSinceKeystroke: 100),
                .writingFluently
            ),
        ])
    func eachRule(context: PredictionContext, expected: Quieting.Reason) {
        #expect(Quieting.reason(context) == expected)
        #expect(Quieting.refuses(context))
    }

    @Test("Being turned off here outranks every other reason, so the report names the one that matters.")
    func prioritised() {
        let everything = PredictionContext(
            typed: "x", caretAtLineEnd: false, hasSelection: true, isComposing: true, isSecure: true,
            isEnabledHere: false)
        #expect(Quieting.reason(everything) == .turnedOffHere)
    }

    @Test("An input method mid-composition does not quiet the suggestion; drawing takes priority.")
    func composingDoesNotQuiet() {
        #expect(Quieting.reason(PredictionContext(typed: "x", isComposing: true)) == nil)
        #expect(!Quieting.refuses(PredictionContext(typed: "x", isComposing: true)))
    }

    @Test("Fluency only quiets prose; a command field answers at once.")
    func fluencyIsProseOnly() {
        let command = PredictionContext(typed: "git c", millisecondsSinceKeystroke: 10)
        let prose = PredictionContext(typed: "Thanks for", isProse: true, millisecondsSinceKeystroke: 10)
        #expect(Quieting.reason(command) == nil)
        #expect(Quieting.reason(prose) == .writingFluently)
    }

    @Test("A prose writer who pauses is answered.")
    func hesitationIsAnswered() {
        let paused = PredictionContext(
            typed: "Thanks for", isProse: true,
            millisecondsSinceKeystroke: Quieting.proseHesitationInMilliseconds)
        #expect(Quieting.reason(paused) == nil)
    }

    @Test("Two rejections is patience; the third is the user saying no.")
    func rejectionsAreCounted() {
        #expect(Quieting.reason(PredictionContext(typed: "x", rejectionsThisSession: 2)) == nil)
        #expect(Quieting.refuses(PredictionContext(typed: "x", rejectionsThisSession: 3)))
    }
}

@Suite("What a set of candidates agrees on")
struct CommonPrefixTests {
    @Test("Nothing agrees on nothing.")
    func empty() {
        #expect(CommonPrefix.of([]).isEmpty)
    }

    @Test("One string agrees with itself entirely.")
    func single() {
        #expect(CommonPrefix.of(["git commit"]) == "git commit")
    }

    @Test("Three commands agree on the part that is safe to insert.")
    func agreement() {
        let shared = CommonPrefix.of(["git commit -m", "git commit --amend", "git commit -a"])
        #expect(shared == "git commit -")
    }

    @Test("Candidates that share nothing agree on nothing.")
    func disagreement() {
        #expect(CommonPrefix.of(["alpha", "beta"]).isEmpty)
    }

    @Test("One string being a prefix of another is the whole agreement.")
    func containment() {
        #expect(CommonPrefix.of(["git", "git commit"]) == "git")
    }

    @Test("An empty string among them leaves nothing agreed.")
    func emptyMember() {
        #expect(CommonPrefix.of(["git commit", ""]).isEmpty)
    }

    @Test("Agreement is by character, so a shared emoji is not cut in half.")
    func unicode() {
        #expect(CommonPrefix.of(["🙂 ship it", "🙂 ship out"]) == "🙂 ship ")
    }

    @Test("A field with no place to draw is quiet for that reason, before anything about its text is asked.")
    func nowhereToDrawIsAReason() {
        #expect(
            Quieting.reason(PredictionContext(typed: "select * from o", canDraw: false)) == .nowhereToDraw)
        #expect(
            Quieting.reason(PredictionContext(typed: "x", hasSelection: true, canDraw: false))
                == .nowhereToDraw)
        #expect(
            Quieting.reason(PredictionContext(typed: "x", isSecure: true, canDraw: false)) == .secureField)
        #expect(Quieting.reason(PredictionContext(typed: "x", canDraw: true)) == nil)
    }
}
