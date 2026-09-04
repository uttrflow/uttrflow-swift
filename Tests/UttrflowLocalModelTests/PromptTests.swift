import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// The register the tests hand the builder, so each test names only the context it is about.
private let casual = Register(
    isMultiline: true, typicalLength: 9, isConversational: true, symbolShare: 0.02, usesSentenceCase: false)

private func message(_ typed: String, _ situation: GenerationSituation) -> String {
    PromptBuilder.message(typed: typed, in: situation, register: casual)
}

/// What the model is told about the moment, laid out without loading a model.
@Suite("The generation prompt")
struct PromptTests {
    @Test(
        "The prompt names the window and register, shows the screen, the person's lines, the earlier text, then the line."
    )
    func everyKindOfContextHasItsPlace() {
        let situation = GenerationSituation(
            application: "Chat", field: "Message", preceding: "earlier paragraph", windowTitle: "Priya",
            surroundings: "Priya: are you coming tonight?", recentLines: ["on my way", "running late, sorry"])
        let prompt = message("yes, ", situation)
        #expect(
            prompt.hasPrefix(
                "In application Chat, window \"Priya\", field Message.\nHints: a multi-line field;"))
        #expect(prompt.contains("lines here run about 9 characters;"))
        #expect(prompt.contains("On screen around the field:\nPriya: are you coming tonight?"))
        #expect(prompt.contains("Lines this person wrote here before:\non my way\nrunning late, sorry"))
        #expect(prompt.contains("The text before the line reads:\nearlier paragraph"))
        #expect(prompt.hasSuffix("Continue this line:\nyes, "))
    }

    @Test("With nothing around the field, the prompt is the situation, the hints and the line.")
    func bareSituationStaysShort() {
        let prompt = message("git c", GenerationSituation(application: "Terminal"))
        #expect(prompt.hasPrefix("In application Terminal.\nHints: "))
        #expect(prompt.hasSuffix("\n\nContinue this line:\ngit c"))
        #expect(!prompt.contains("On screen"))
        #expect(!prompt.contains("wrote here"))
    }

    @Test(
        "The screen and the person's lines come before the earlier text, so the line to finish is always last."
    )
    func theLineIsAlwaysLast() {
        let situation = GenerationSituation(
            application: "Notes", document: "Ideas", preceding: "before", surroundings: "around")
        let prompt = message("and", situation)
        #expect(prompt.range(of: "around")!.lowerBound < prompt.range(of: "The text before")!.lowerBound)
        #expect(prompt.hasSuffix("\nand"))
        #expect(prompt.contains("document Ideas"))
    }

    @Test(
        "Over budget, the screen is cut first and from the front, the oldest lines next, and the line never.")
    func theBudgetTrimsTheFarthestContextFirst() {
        let screen = String(repeating: "far ", count: 2_000) + "near the field"
        let lines = (0..<40).map { "line number \($0) of what this person wrote here before" }
        let situation = GenerationSituation(
            application: "Chat", preceding: String(repeating: "p", count: 3_000) + " end",
            surroundings: screen, recentLines: lines)
        let typed = String(repeating: "t", count: 300)
        let prompt = message(typed, situation)
        #expect(prompt.count <= PromptBuilder.budgetInCharacters + 200)
        #expect(prompt.hasSuffix("Continue this line:\n\(typed)"))
        #expect(prompt.contains("near the field"))
        #expect(prompt.contains("line number 0 of"))
        #expect(!prompt.contains("line number 39 of"))
        #expect(prompt.contains(" end\n"))
    }

    @Test("Trimming keeps the end of a text and the newest lines, and nothing at all when there is no room.")
    func trimmingKeepsWhatIsNearest() {
        #expect(PromptBuilder.tail("abcdef", within: 3) == "def")
        #expect(PromptBuilder.tail("abc", within: 10) == "abc")
        #expect(PromptBuilder.tail("abc", within: 0) == "")
        #expect(PromptBuilder.newest(["new", "older", "oldest"], within: 10) == ["new", "older"])
        #expect(PromptBuilder.newest(["new"], within: 2) == [])
    }
}
