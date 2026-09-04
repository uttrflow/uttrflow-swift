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
        #expect(prompt.hasSuffix("on one line:\nyes, "))
    }

    @Test("With nothing around the field, the prompt is the situation, the hints and the line.")
    func bareSituationStaysShort() {
        let prompt = message("git c", GenerationSituation(application: "Terminal"))
        #expect(prompt.hasPrefix("In application Terminal.\nHints: "))
        let closing = "Continue this line with the single most likely completion, on one line:\ngit c"
        #expect(prompt.hasSuffix("\n\n" + closing))
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
        #expect(prompt.hasSuffix("on one line:\n\(typed)"))
        #expect(prompt.contains("near the field"))
        #expect(prompt.contains("line number 0 of"))
        #expect(!prompt.contains("line number 39 of"))
        #expect(prompt.contains(" end\n"))
    }

    @Test(
        "The pass asks for one line by default, and for others only once a line is on screen to differ from.")
    func theAskNamesWhatIsWanted() {
        let situation = GenerationSituation(application: "Terminal")
        let one = PromptBuilder.message(typed: "git c", in: situation, register: casual)
        #expect(
            one.hasSuffix("Continue this line with the single most likely completion, on one line:\ngit c"))
        let others = PromptBuilder.message(
            typed: "git c", in: situation, register: casual, asking: .others(excluding: "git commit -m"))
        #expect(others.contains("up to three other ways"))
        #expect(others.contains("different from \"git commit -m\""))
        #expect(others.hasSuffix("one per line:\ngit c"))
    }

    @Test(
        "A pass for one line ends at the newline the model writes; a pass for several runs on to its budget.")
    func oneLineEndsAtItsNewline() {
        #expect(Ask.one.stopStrings == ["\n"])
        #expect(Ask.others(excluding: "git commit -m").stopStrings == nil)
    }

    @Test(
        "A pass budgets the echo of the line for every answer on top of the completion, which alone is capped."
    )
    func theBudgetPaysForTheEcho() {
        #expect(MLXCandidateScorer.tokenBudget(perLine: 24, lines: 1, echo: 10, cap: 128) == 34)
        #expect(MLXCandidateScorer.tokenBudget(perLine: 60, lines: 3, echo: 5, cap: 128) == 143)
        #expect(MLXCandidateScorer.tokenBudget(perLine: 96, lines: 1, echo: 0, cap: 128) == 96)
    }

    @Test(
        "Trimming keeps the end of a text, the start of a name and the newest lines, and nothing when there is no room."
    )
    func trimmingKeepsWhatIsNearest() {
        #expect(PromptBuilder.tail("abcdef", within: 3) == "def")
        #expect(PromptBuilder.tail("abc", within: 10) == "abc")
        #expect(PromptBuilder.tail("abc", within: 0) == "")
        #expect(PromptBuilder.head("abcdef", within: 3) == "abc")
        #expect(PromptBuilder.head("abc", within: 0) == "")
        #expect(PromptBuilder.newest(["new", "older", "oldest"], within: 10) == ["new", "older"])
        #expect(PromptBuilder.newest(["new"], within: 1) == [])
        #expect(PromptBuilder.newest([], within: 100) == [])
    }

    @Test(
        "A newest line too long for its allowance is kept cut down rather than dropped with the person's whole voice."
    )
    func theNewestLineIsCutRatherThanDropped() {
        let long = String(repeating: "n", count: 520)
        #expect(PromptBuilder.newest([long, "short"], within: 500) == [String(repeating: "n", count: 499)])
        #expect(PromptBuilder.newest(["newest line"], within: 4) == ["new"])
    }

    @Test(
        "A window title as long as a page keeps its first characters only, so the person's lines still fit.")
    func aLongWindowTitleIsCapped() {
        let title = String(repeating: "t", count: 2_000)
        let situation = GenerationSituation(
            application: "Safari", field: String(repeating: "f", count: 500), windowTitle: title,
            surroundings: "Search or enter website name", recentLines: ["on my way", "running late, sorry"])
        let prompt = message("yes, ", situation)
        #expect(prompt.count <= PromptBuilder.budgetInCharacters + 200)
        #expect(
            prompt.contains(
                "window \"" + String(repeating: "t", count: PromptBuilder.locatorCap) + "\", field"))
        #expect(!prompt.contains(String(repeating: "t", count: PromptBuilder.locatorCap + 1)))
        #expect(prompt.contains("Lines this person wrote here before:\non my way\nrunning late, sorry"))
        #expect(prompt.contains("On screen around the field:\nSearch or enter website name"))
    }
}
