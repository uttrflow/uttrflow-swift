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
        // A terse person's length is not quoted for a reply, so the model is not told to stop at a word.
        #expect(!prompt.contains("lines here run about"))
        #expect(prompt.contains("On screen around the field:\nPriya: are you coming tonight?"))
        #expect(prompt.contains("Lines this person wrote here before:\non my way\nrunning late, sorry"))
        #expect(prompt.contains("The text before the line reads:\nearlier paragraph"))
        #expect(prompt.hasSuffix("on one line, finishing the whole message:\nyes, "))
    }

    @Test("With nothing around the field, the prompt is the situation, the hints and the line.")
    func bareSituationStaysShort() {
        let prompt = message("git c", GenerationSituation(application: "Terminal"))
        #expect(prompt.hasPrefix("In application Terminal.\nHints: "))
        let closing =
            "Continue this reply with the single most likely completion, on one line, finishing the whole message:\ngit c"
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
        "Over budget, the screen is cut to its nearest lines, the oldest lines go first, and the line never.")
    func theBudgetTrimsTheFarthestContextFirst() {
        let screen =
            (0..<400).map { "far paragraph \($0) of the page, 2026-09-14" }.joined(separator: "\n")
            + "\nnear the field"
        let lines = (0..<40).map { "line number \($0) of what this person wrote here before" }
        let situation = GenerationSituation(
            application: "Chat", preceding: "a short start", surroundings: screen, recentLines: lines)
        let typed = String(repeating: "t", count: 300)
        let prompt = message(typed, situation)
        #expect(prompt.hasSuffix("finishing the whole message:\n\(typed)"))
        #expect(prompt.contains("near the field\n\n"))
        #expect(!prompt.contains("far paragraph 0 "))
        #expect(prompt.contains("line number 0 of"))
        #expect(!prompt.contains("line number 39 of"))
        #expect(prompt.contains("The text before the line reads:\na short start"))
        let context = PromptBuilder.context(for: situation)
        #expect(
            PromptBuilder.estimatedTokens(context.screen) + PromptBuilder.estimatedTokens(context.recent)
                + PromptBuilder.estimatedTokens(context.preceding) + 3 * PromptBuilder.headingCost
                <= PromptBuilder.contextBudgetInTokens)
    }

    @Test("A field whose own text before the line says enough is shown without the page around it.")
    func ownTextLeavesThePageOut() {
        let screen = "Home\nDocs\nPricing\nThe configuration file is read once at startup."
        let short = GenerationSituation(application: "Browser", preceding: "Two words", surroundings: screen)
        #expect(message("and", short).contains("On screen around the field:\nHome\nDocs"))
        let paragraph = String(
            repeating:
                "The watcher resolves the path twice and registers a second watcher before the first is gone. ",
            count: 4)
        let long = GenerationSituation(application: "Browser", preceding: paragraph, surroundings: screen)
        let prompt = message("and", long)
        #expect(!prompt.contains("On screen"))
        #expect(prompt.contains("registers a second watcher before the first is gone. \n\n"))
    }

    @Test("A control repeated down the page is shown once, where it sits nearest the field.")
    func repeatedControlsAreShownOnce() {
        let screen = "First comment\nReply\nShare\nSecond comment\nReply\nShare\nLeave a comment"
        let shown = PromptBuilder.nearestLines(screen, within: 100)
        #expect(shown == "First comment\nSecond comment\nReply\nShare\nLeave a comment")
    }

    @Test("The estimate errs high for prose and counts digits and marks one by one.")
    func theEstimateCountsWordsDigitsAndMarks() {
        #expect(PromptBuilder.estimatedTokens("") == 0)
        #expect(PromptBuilder.estimatedTokens("word") == 1)
        #expect(PromptBuilder.estimatedTokens("words") == 2)
        #expect(PromptBuilder.estimatedTokens("a b") == 2)
        #expect(PromptBuilder.estimatedTokens("a  b") == 3)
        #expect(PromptBuilder.estimatedTokens("v 4.2") == 5)
        #expect(PromptBuilder.estimatedTokens("line\n") == 2)
        #expect(PromptBuilder.estimatedTokens("नमस्ते") == 3)
        #expect(PromptBuilder.estimatedTokens("🙏") == 1)
    }

    @Test(
        "The pass asks for one line by default, and for others only once a line is on screen to differ from.")
    func theAskNamesWhatIsWanted() {
        let situation = GenerationSituation(application: "Terminal")
        let one = PromptBuilder.message(typed: "git c", in: situation, register: casual)
        #expect(
            one.hasSuffix(
                "Continue this reply with the single most likely completion, on one line, finishing the whole message:\ngit c"
            ))
        // The instruction at the line names the register's kind, so a shell asks for a command and an address bar for an address.
        let shell = Register(
            isMultiline: false, typicalLength: 19, isConversational: false, symbolShare: 0.14,
            usesSentenceCase: nil)
        let command = PromptBuilder.message(typed: "git c", in: situation, register: shell)
        #expect(command.contains("Continue this command, query or line of code with"))
        #expect(command.contains("on one line:\ngit c") && !command.contains("whole message"))
        let others = PromptBuilder.message(
            typed: "git c", in: situation, register: casual, asking: .others(excluding: "git commit -m"))
        #expect(others.contains("up to three other ways to finish this reply"))
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
        "One line opens the model's turn with the line up to its last word and owes that word; several lines open with nothing."
    )
    func oneLineOpensUpToItsLastWord() {
        #expect(
            Ask.one.opening(of: "git c") == Ask.Opening(written: "git", owed: " c", isWordComplete: false))
        #expect(
            Ask.one.opening(of: "npm install ")
                == Ask.Opening(written: "npm", owed: " install", isWordComplete: true))
        #expect(
            Ask.one.opening(of: "The next rel")
                == Ask.Opening(written: "The next", owed: " rel", isWordComplete: false))
        #expect(
            Ask.one.opening(of: "    return a ")
                == Ask.Opening(written: "    return", owed: " a", isWordComplete: true))
        #expect(
            Ask.one.opening(of: "stackover")
                == Ask.Opening(written: "", owed: "stackover", isWordComplete: false))
        #expect(
            MLXCandidateScorer.wholeWords(of: " members (id, name) VALUES (1, 'Ali")
                == " members (id, name) VALUES (1,")
        #expect(MLXCandidateScorer.wholeWords(of: "figma.com/file/jW66") == "")
        #expect(
            Ask.one.opening(of: "happy birthday 🎂  ")
                == Ask.Opening(written: "happy birthday", owed: " 🎂", isWordComplete: true))
        #expect(Ask.one.opening(of: "   ") == nil)
        // A word closing a sentence or statement may end the line, unless a space after it asks for more.
        #expect(Ask.one.opening(of: "See you at 8!")?.mayEnd == true)
        #expect(Ask.one.opening(of: "SELECT count(*) FROM orders;")?.mayEnd == true)
        #expect(Ask.one.opening(of: "See you at 8! ")?.mayEnd == false)
        #expect(Ask.one.opening(of: "git c")?.mayEnd == false)
        #expect(Ask.others(excluding: "git commit -m").opening(of: "git c") == nil)
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
        #expect(PromptBuilder.tail("one two three four", within: 2) == "hree four")
        #expect(PromptBuilder.tail("abc", within: 10) == "abc")
        #expect(PromptBuilder.tail("abc", within: 0) == "")
        #expect(PromptBuilder.leading("one two three four", within: 2) == "one two ")
        #expect(PromptBuilder.leading("abc", within: 0) == "")
        #expect(PromptBuilder.nearestLines("far\nnear", within: 1) == "")
        #expect(PromptBuilder.nearestLines("far\n  \nnear", within: 5) == "far\nnear")
        #expect(PromptBuilder.head("abcdef", within: 3) == "abc")
        #expect(PromptBuilder.head("abc", within: 0) == "")
        #expect(PromptBuilder.newest(["new", "older", "oldest"], within: 5) == ["new", "older"])
        #expect(PromptBuilder.newest(["new"], within: 1) == [])
        #expect(PromptBuilder.newest([], within: 100) == [])
    }

    @Test(
        "A newest line too long for its allowance is kept cut down rather than dropped with the person's whole voice."
    )
    func theNewestLineIsCutRatherThanDropped() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        let kept = PromptBuilder.newest([long, "short"], within: 21)
        #expect(kept.count == 1 && long.hasPrefix(kept[0]))
        #expect(PromptBuilder.estimatedTokens(kept[0]) == 20)
        #expect(PromptBuilder.newest(["newest line"], within: 2) == ["newe"])
        #expect(PromptBuilder.newest(["🙏🙏"], within: 1) == [])
        #expect(PromptBuilder.nearestLines(long, within: 11).hasSuffix("word word"))
    }

    @Test(
        "A window title as long as a page keeps its first characters only, so the person's lines still fit.")
    func aLongWindowTitleIsCapped() {
        let title = String(repeating: "t", count: 2_000)
        let situation = GenerationSituation(
            application: "Safari", field: String(repeating: "f", count: 500), windowTitle: title,
            surroundings: "Search or enter website name", recentLines: ["on my way", "running late, sorry"])
        let prompt = message("yes, ", situation)
        #expect(
            prompt.contains(
                "window \"" + String(repeating: "t", count: PromptBuilder.locatorCap) + "\", field"))
        #expect(!prompt.contains(String(repeating: "t", count: PromptBuilder.locatorCap + 1)))
        #expect(prompt.contains("Lines this person wrote here before:\non my way\nrunning late, sorry"))
        #expect(prompt.contains("On screen around the field:\nSearch or enter website name"))
    }

    @Test("The person's earlier lines in another script are not shown to the model.")
    func nonLatinRecentLinesAreNotShown() {
        let situation = GenerationSituation(application: "Chat", recentLines: ["haan bilkul", "नहीं जाना"])
        let prompt = message("kal ", situation)
        #expect(prompt.contains("Lines this person wrote here before:\nhaan bilkul"))
        #expect(!prompt.contains("नहीं"))
    }

    @Test(
        "Another script in the context tells the model to write English or romanised Hinglish in the Latin alphabet."
    )
    func nonLatinContextNamesTheScript() {
        let thread = GenerationSituation(application: "Chat", surroundings: "Rahul: कल मिलते हैं?")
        #expect(message("haan ", thread).contains("\n" + PromptBuilder.scriptInstruction + "\n"))
        #expect(PromptBuilder.scriptInstruction.contains("Write only English in the Latin alphabet"))
        #expect(PromptBuilder.scriptInstruction.contains("romanised Hinglish"))
        let titled = GenerationSituation(application: "Chat", windowTitle: "राहुल")
        #expect(message("haan ", titled).contains(PromptBuilder.scriptInstruction))
        let latin = GenerationSituation(
            application: "Chat", field: "Message", preceding: "café", windowTitle: "Rahul",
            surroundings: "Rahul: kal milte hain? 👍🏽", recentLines: ["haan bilkul"])
        #expect(!message("haan ", latin).contains(PromptBuilder.scriptInstruction))
    }
}
