import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("SpelledInitialismPass")
struct SpelledInitialismPassTests {
    private let sut = SpelledInitialismPass()

    @Test(
        "joins spoken letter names and writes common dotted abbreviations",
        arguments: [
            ("the a p i is down", "The API is down."),
            ("a p i is down", "API is down."),
            ("i e the main one", "I.e. the main one."),
            ("bring snacks e g chips", "Bring snacks e.g. chips."),
            ("we need it a s a p", "We need it ASAP."),
            ("open a p r for it", "Open APR for it."),
            ("a pen is here", "A pen is here."),
            ("so i think", "So I think."),
        ])
    func cleans(input: String, expected: String) {
        #expect(
            CleaningPipeline(passes: [sut, FirstWordPass(), TerminalStopPass()])
                .run(Draft(text: input)).text == expected)
    }

    @Test("leaves a stammered pronoun as two words rather than an initialism")
    func stammeredPronoun() {
        #expect(sut.apply(Draft(text: "I I think we should ship it")).text == "I I think we should ship it")
    }

    @Test(
        "never reads a cut-off word as a letter name",
        arguments: [
            ("I w- I went", "I w- I went"),
            ("so I t- to go", "so I t- to go"),
            ("I s- so", "I s- so"),
            ("I B M", "IBM"),
        ])
    func cutOff(input: String, expected: String) {
        #expect(sut.apply(Draft(text: input)).text == expected)
    }

    @Test(
        "keeps a run made only of everyday words as words",
        arguments: [
            "you are coming tomorrow", "how are you", "i know you are busy", "see you later",
            "i see you tomorrow", "so you see it works", "oh i see", "oh why", "why you are late",
            "she asked me why i left early", "did you see the game", "be you",
        ])
    func everydayRun(input: String) {
        #expect(sut.apply(Draft(text: input)).text == input)
    }

    @Test(
        "joins a run once any name is only a letter",
        arguments: [("i b m", "IBM"), ("u s a", "USA"), ("you r l", "URL"), ("see s s", "CSS")])
    func spelledRun(input: String, expected: String) {
        #expect(sut.apply(Draft(text: input)).text == expected)
    }

    @Test(
        "does not treat i adjacent to a letter name as the pronoun",
        arguments: [
            ("we said i e is the main one", "we said i.e. is the main one"),
            ("we said a p i is down", "we said API is down"),
        ])
    func adjacentI(input: String, expected: String) {
        let joined = sut.apply(Draft(text: input))
        let cased = FirstWordPass().apply(joined)
        #expect(WordShape.withoutTrailingStop(cased.text) == expected)
    }

    @Test(
        "does not join an article a to its following single letter",
        arguments: ["a p", "a pen", "we need a p", "we need a s a p"])
    func protectsArticle(input: String) {
        let result = CleaningPipeline(passes: [sut]).run(Draft(text: input)).text
        #expect(result == input)
    }

    @Test("distinguishes an article a from the letter name A at a sentence start")
    func articleAndInitialism() {
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: "a p i")).text == "API")
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: "we need a p")).text == "we need a p")
    }

    @Test(
        "joins split AM only after a clock expression",
        arguments: [
            ("nine a m", "nine AM"),
            ("6:15 a m", "6:15 AM"),
            ("five o'clock a m", "five o'clock AM"),
            ("we need a m", "we need a m"),
        ])
    func splitAMContext(input: String, expected: String) {
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: input)).text == expected)
    }

    @Test("does not join letters separated by a removed filler")
    func removedFillerBreaksInitialism() {
        var draft = Draft(text: "we said e uh g")
        draft.remove(at: 3, by: .fillers)
        #expect(sut.apply(draft).text == "we said e g")
    }

    @Test("does not treat i after a removed filler as part of the previous letter run")
    func removedFillerKeepsPronounI() {
        var draft = Draft(text: "we said p uh i")
        draft.remove(at: 3, by: .fillers)
        #expect(FirstWordPass().apply(draft).text == "we said p I")
    }
}
