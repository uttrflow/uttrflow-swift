import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// A vocabulary small enough to name every token: 0 " Sou", 1 "rces", 2 " Scr", 3 "ipts", 4 " Sources", 5 " Sour", 6 " x", 7 newline, 8 "rces && make", 9 "rcesx".
private let vocabulary = TokenHealing.Vocabulary(
    texts: [" Sou", "rces", " Scr", "ipts", " Sources", " Sour", " x", "\n", "rces && make", "rcesx"],
    ending: [7])

@Suite("Holding a pass to one of the machine's values")
struct TokenChoiceTests {
    @Test(
        "Only tokens that keep to some choice may be produced: part of one, or all of one and then a space.")
    func onlyTheChoicesAreAllowed() {
        let choice = TokenChoice(vocabulary: vocabulary, choices: [" Sources", " Scripts"])
        let mask = choice.mask(width: vocabulary.bytes.count)
        #expect(mask?.map { $0 == 0 } == [true, false, true, false, true, true, false, false, false, false])
    }

    @Test("A token written narrows the choices to those it began, and the rest of each is what remains.")
    func writingNarrowsTheChoices() {
        var choice = TokenChoice(vocabulary: vocabulary, choices: [" Sources", " Scripts", " Sour"])
        choice.took(" Sou")
        #expect(choice.remaining == [Array("rces".utf8), Array("r".utf8)])
        #expect(!choice.isFree)
        // Only the rest of a begun choice may follow; a token that continues one and then leaves a space may too.
        #expect(
            choice.mask(width: vocabulary.bytes.count)?.map { $0 == 0 } == [
                false, true, false, false, false, false, false, false, true, false,
            ])
    }

    @Test("A choice written whole frees the model, whether the last token ended it or ran on past it.")
    func aWholeChoiceFreesTheModel() {
        var exact = TokenChoice(vocabulary: vocabulary, choices: [" Sources"])
        exact.took(" Sources")
        #expect(exact.isFree)
        #expect(exact.mask(width: 4) == nil)
        var past = TokenChoice(vocabulary: vocabulary, choices: [" Sources"])
        past.took(" Sou")
        past.took("rces && make")
        #expect(past.isFree)
    }

    @Test(
        "A token the mask should have refused leaves nothing to hold the model to, so it is left free rather than stuck."
    )
    func aStrayTokenFreesTheModel() {
        var choice = TokenChoice(vocabulary: vocabulary, choices: [" Sources"])
        choice.took(" x")
        #expect(choice.isFree)
    }

    @Test("Choices no token can keep to leave the logits untouched, and an empty choice is no choice.")
    func unmatchableChoicesLeaveTheModelFree() {
        let choice = TokenChoice(vocabulary: vocabulary, choices: ["zzz"])
        #expect(choice.mask(width: vocabulary.bytes.count) == nil)
        #expect(TokenChoice(vocabulary: vocabulary, choices: [""]).remaining.isEmpty)
    }

    @Test(
        "A word still open is one of the values, led as the typed word was; a word finished is written and the value follows a space."
    )
    func theTurnOpensBeforeTheChosenWord() throws {
        let open = try #require(Ask.one.opening(of: "cd Sou"))
        #expect(
            MLXCandidateScorer.choice(of: ["Sources", "Scripts"], at: open)
                == MLXCandidateScorer.Choice(written: "cd", choices: [" Sources", " Scripts"]))
        let finished = try #require(Ask.one.opening(of: "cd "))
        #expect(
            MLXCandidateScorer.choice(of: ["Sources"], at: finished)
                == MLXCandidateScorer.Choice(written: "cd", choices: [" Sources"]))
        #expect(MLXCandidateScorer.choice(of: [], at: open) == nil)
    }

    @Test("The prompt names the values the next word must be one of, and only when there are any.")
    func thePromptNamesTheChoices() {
        let register = Register.infer(from: GenerationSituation(application: "Terminal"), typed: "cd ")
        let held = GenerationSituation(application: "Terminal", choices: ["Sources", "Scripts"])
        let message = PromptBuilder.message(typed: "cd ", in: held, register: register)
        #expect(message.contains("The next word is one of these, exactly as written: Sources, Scripts."))
        let free = PromptBuilder.message(
            typed: "cd ", in: GenerationSituation(application: "Terminal"), register: register)
        #expect(!free.contains("The next word is one of these"))
        // The choosing turn's list is told to the model once; a pass for alternatives is never held to it.
        let others = PromptBuilder.message(
            typed: "cd ", in: held, register: register, asking: .others(excluding: "cd Sources"))
        #expect(!others.contains("The next word is one of these"))
    }
}
