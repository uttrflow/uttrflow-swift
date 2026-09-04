import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// What the model is told about the moment, laid out without loading a model.
@Suite("The generation prompt")
struct PromptTests {
    @Test(
        "The prompt names the window, shows the screen, the person's lines and the earlier text, and ends with the line."
    )
    func everyKindOfContextHasItsPlace() {
        let situation = GenerationSituation(
            application: "Chat", field: "Message", preceding: "earlier paragraph", windowTitle: "Priya",
            surroundings: "Priya: are you coming tonight?", recentLines: ["on my way", "running late, sorry"])
        let prompt = MLXCandidateScorer.prompt(typed: "yes, ", in: situation)
        #expect(prompt.hasPrefix("In application Chat, window \"Priya\", field Message."))
        #expect(prompt.contains("On screen around the field:\nPriya: are you coming tonight?"))
        #expect(prompt.contains("Lines this person wrote here before:\non my way\nrunning late, sorry"))
        #expect(prompt.contains("The text before the line reads:\nearlier paragraph"))
        #expect(prompt.hasSuffix("Continue this line:\nyes, "))
    }

    @Test("With nothing around the field, the prompt is the bare situation and the line.")
    func bareSituationStaysShort() {
        let prompt = MLXCandidateScorer.prompt(
            typed: "git c", in: GenerationSituation(application: "Terminal"))
        #expect(prompt == "In application Terminal.\n\nContinue this line:\ngit c")
    }

    @Test(
        "The screen and the person's lines come before the earlier text, so the line to finish is always last."
    )
    func theLineIsAlwaysLast() {
        let situation = GenerationSituation(
            application: "Notes", document: "Ideas", preceding: "before", surroundings: "around")
        let prompt = MLXCandidateScorer.prompt(typed: "and", in: situation)
        let around = prompt.range(of: "around")!.lowerBound
        let before = prompt.range(of: "The text before")!.lowerBound
        #expect(around < before)
        #expect(prompt.hasSuffix("\nand"))
        #expect(prompt.contains("document Ideas"))
    }
}
