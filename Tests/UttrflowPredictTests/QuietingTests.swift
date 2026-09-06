import Foundation
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

    @Test("Two rejections is patience; the third is the user saying no.")
    func rejectionsAreCounted() {
        #expect(Quieting.reason(PredictionContext(typed: "x", rejectionsThisSession: 2)) == nil)
        #expect(Quieting.refuses(PredictionContext(typed: "x", rejectionsThisSession: 3)))
    }
}

/// One moment built from a seed, with every gate's input drawn at random.
struct QuietingCase: Sendable, CustomTestStringConvertible {
    /// The seed the moment was built from, which a failure names.
    let seed: Int
    /// The moment itself.
    let context: PredictionContext

    /// One moment drawn from the seed.
    init(seed: Int) {
        var random = Seeded(seed: seed)
        self.seed = seed
        context = PredictionContext(
            typed: random.pick(["", "git c", "hello"]), caretAtLineEnd: random.chance(0.7),
            hasSelection: random.chance(0.2), isComposing: random.chance(0.3), isSecure: random.chance(0.2),
            isProse: random.chance(0.5),
            millisecondsSinceKeystroke: random.pick([0, 200, 399, 400, 401, 5_000]),
            isEnabledHere: random.chance(0.8), isMinimised: random.chance(0.2),
            rejectionsThisSession: Int.random(in: 0...5, using: &random))
    }

    /// What a failure is named after, which is the seed that reproduces it.
    var testDescription: String { "seed \(seed)" }
}

@Suite("The quieting rules over random moments")
struct QuietingPropertyTests {
    @Test(
        "The reason is the first rule that fires, in order, and composition is never one of them.",
        arguments: (0..<300).map(QuietingCase.init))
    func reasonIsTheFirstRule(sample: QuietingCase) {
        let context = sample.context
        let expected: Quieting.Reason? =
            if !context.isEnabledHere {
                .turnedOffHere
            } else if context.isSecure {
                .secureField
            } else if context.hasSelection {
                .textSelected
            } else if !context.caretAtLineEnd {
                .caretInsideText
            } else if context.rejectionsThisSession >= Quieting.rejectionsBeforeSilence {
                .rejectedTooOften
            } else if context.isProse,
                context.millisecondsSinceKeystroke < Quieting.proseHesitationInMilliseconds
            {
                .writingFluently
            } else {
                nil
            }
        #expect(Quieting.reason(context) == expected)
        #expect(Quieting.refuses(context) == (expected != nil))
        if expected != nil {
            let strong = [remembered("git commit -m", count: 40)]
            #expect(PredictionEngine.suggestion(from: strong, in: context, now: moment) == .silent)
        }
    }
}
