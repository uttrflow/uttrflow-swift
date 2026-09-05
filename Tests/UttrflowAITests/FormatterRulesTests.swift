import Testing

@testable import UttrflowAI
@testable import UttrflowCore

@Suite("FirstWordRule")
struct FirstWordRuleTests {
    private func fromCaret(
        _ text: String, state: InsertionPoint.SentenceState, onScreen: [String] = []
    ) -> String {
        FirstWordRule.apply(
            text, heard: text.lowercased(), policy: .fromInsertionPoint, state: state, onScreen: onScreen)
    }

    @Test("lower-cases a common first word when the caret sits mid-sentence")
    func lowersMidSentence() {
        #expect(fromCaret("The build failed.", state: .midSentence) == "the build failed.")
        #expect(fromCaret("  Because of that.", state: .midSentence) == "  because of that.")
    }

    @Test(
        "leaves the first word alone anywhere but mid-sentence",
        arguments: [InsertionPoint.SentenceState.startOfText, .startOfSentence, .unknown]
    )
    func keepsCapitalElsewhere(state: InsertionPoint.SentenceState) {
        #expect(fromCaret("The build failed.", state: state) == "The build failed.")
    }

    @Test(
        "keeps the capital of I, its contractions and an acronym mid-sentence",
        arguments: [
            "I think so.", "I'll be there.", "I\u{2019}m late.", "API returns JSON.", "NASA said so.",
        ]
    )
    func exemptions(text: String) {
        #expect(fromCaret(text, state: .midSentence) == text)
    }

    @Test("does nothing to a first word that has no letter, or to an empty text")
    func nothingToLower() {
        #expect(fromCaret("42 things.", state: .midSentence) == "42 things.")
        #expect(fromCaret("\"Quoted\" words.", state: .midSentence) == "\"Quoted\" words.")
        #expect(fromCaret("", state: .midSentence) == "")
        #expect(fromCaret("   ", state: .midSentence) == "   ")
    }

    @Test("always capital gives the first character a capital whatever the caret says")
    func alwaysCapital() {
        #expect(
            FirstWordRule.apply(
                "hello there", heard: "hello there", policy: .alwaysCapital, state: .midSentence)
                == "Hello there")
        #expect(
            FirstWordRule.apply("42 things", heard: "42 things", policy: .alwaysCapital, state: .unknown)
                == "42 things")
        #expect(FirstWordRule.apply("", heard: "", policy: .alwaysCapital, state: .unknown) == "")
    }

    @Test("as spoken copies the case the first word was heard in, past any filler before it")
    func asSpoken() {
        #expect(
            FirstWordRule.apply(
                "Total revenue", heard: "um total revenue", policy: .asSpoken, state: .unknown)
                == "total revenue")
        #expect(
            FirstWordRule.apply("Total revenue", heard: "total revenue", policy: .asSpoken, state: .unknown)
                == "total revenue")
        #expect(
            FirstWordRule.apply("total revenue", heard: "Total revenue", policy: .asSpoken, state: .unknown)
                == "Total revenue")
        #expect(
            FirstWordRule.apply("Total, revenue", heard: "total revenue", policy: .asSpoken, state: .unknown)
                == "total, revenue")
    }

    @Test("as spoken leaves a first word the model changed, or that has no letters, alone")
    func asSpokenOnlyForTheSameWord() {
        #expect(
            FirstWordRule.apply("Sum of revenue", heard: "total revenue", policy: .asSpoken, state: .unknown)
                == "Sum of revenue")
        #expect(
            FirstWordRule.apply("42 things", heard: "42 things", policy: .asSpoken, state: .unknown)
                == "42 things")
        #expect(FirstWordRule.apply("", heard: "total", policy: .asSpoken, state: .unknown) == "")
        #expect(
            FirstWordRule.apply(
                "\"Total\" revenue", heard: "total revenue", policy: .asSpoken, state: .unknown)
                == "\"Total\" revenue")
    }

    @Test("keeps a first word that reappears capitalised later in the output, off a sentence start")
    func keepsNameSeenAgainInOutput() {
        #expect(
            fromCaret("John said the build failed, so John fixed it.", state: .midSentence)
                == "John said the build failed, so John fixed it.")
        #expect(
            fromCaret("Because the build failed. Because of that.", state: .midSentence)
                == "because the build failed. Because of that.")
    }

    @Test("keeps a first word that the screen shows capitalised, in the title or around the caret")
    func keepsNameSeenOnScreen() {
        let text = "John said the build failed."
        #expect(fromCaret(text, state: .midSentence, onScreen: ["Chat with John"]) == text)
        #expect(fromCaret(text, state: .midSentence, onScreen: ["", "Ask (John) tomorrow."]) == text)
        #expect(
            fromCaret(text, state: .midSentence, onScreen: ["Notes"]) == "john said the build failed.")
    }

    @Test(
        "lowers a common first word mid-sentence, and keeps I and an acronym, whatever the screen shows",
        arguments: [
            ("Because the build failed.", "because the build failed."),
            ("I'll fix it.", "I'll fix it."), ("API returns JSON.", "API returns JSON."),
        ]
    )
    func lowersOrKeepsWithScreen(text: String, expected: String) {
        let screen = ["Because - Notes", "ok. Because"]
        #expect(fromCaret(text, state: .midSentence, onScreen: screen) == expected)
    }

    @Test("sights a name off a sentence start only, and not in a text capitalised throughout")
    func looksLikeName() {
        #expect(FirstWordRule.looksLikeName("John", in: ["so John said"]))
        #expect(FirstWordRule.looksLikeName("john", in: ["so \"John\" said"]))
        #expect(!FirstWordRule.looksLikeName("John", in: ["so john said"]))
        #expect(!FirstWordRule.looksLikeName("John", in: ["John said", "ok. John said", "ok\nJohn said"]))
        #expect(!FirstWordRule.looksLikeName("John", in: ["Mail - John Smith"]))
        #expect(!FirstWordRule.looksLikeName("...", in: ["so ... said"]))
        #expect(!FirstWordRule.looksLikeName("John", in: []))
    }

    @Test("names an exemption exactly: a lone capital or a run of two or more")
    func keepsCapital() {
        #expect(FirstWordRule.keepsCapital("I"))
        #expect(FirstWordRule.keepsCapital("I'd"))
        #expect(FirstWordRule.keepsCapital("USB-C"))
        #expect(!FirstWordRule.keepsCapital("A"))
        #expect(!FirstWordRule.keepsCapital("It"))
        #expect(!FirstWordRule.keepsCapital("Ice"))
    }
}

@Suite("TerminalStopRule")
struct TerminalStopRuleTests {
    @Test("always finishes a sentence the way the tidier does")
    func always() {
        #expect(TerminalStopRule.apply("ship it", policy: .always) == "ship it.")
        #expect(TerminalStopRule.apply("ship it?", policy: .always) == "ship it?")
    }

    @Test("never adds a stop, and takes back one that was put there")
    func never() {
        #expect(TerminalStopRule.apply("total revenue", policy: .never) == "total revenue")
        #expect(TerminalStopRule.apply("total revenue.", policy: .never) == "total revenue")
        #expect(TerminalStopRule.apply("return x;", policy: .never) == "return x;")
    }

    @Test(
        "never keeps a question mark, an exclamation mark and an ellipsis",
        arguments: ["ready?", "go!", "wait...", "wait…"])
    func neverKeepsOtherMarks(text: String) {
        #expect(TerminalStopRule.apply(text, policy: .never) == text)
    }

    @Test("a short message has its stop withheld, whoever put it there")
    func shortMessages() {
        let policy = TerminalStopPolicy.offForShortMessages(sentences: 2)
        #expect(TerminalStopRule.apply("on my way", policy: policy) == "on my way")
        #expect(TerminalStopRule.apply("On my way.", policy: policy) == "On my way")
        #expect(
            TerminalStopRule.apply("Are you around? I should be there in ten.", policy: policy)
                == "Are you around? I should be there in ten")
    }

    @Test("a longer message keeps its stop, and gains one it lacked")
    func longerMessages() {
        let policy = TerminalStopPolicy.offForShortMessages(sentences: 2)
        #expect(TerminalStopRule.apply("One. Two. Three.", policy: policy) == "One. Two. Three.")
        #expect(TerminalStopRule.apply("One. Two. Three", policy: policy) == "One. Two. Three.")
    }

    @Test(
        "a short message keeps a question mark, an exclamation mark and an ellipsis",
        arguments: ["Ready?", "Go!", "Well…"])
    func shortMessagesKeepOtherMarks(text: String) {
        #expect(TerminalStopRule.apply(text, policy: .offForShortMessages(sentences: 2)) == text)
    }

    @Test(
        "counts sentences by their marks, with a decimal point and a run of marks not counting",
        arguments: [
            ("", 0), ("   ", 0), ("one", 1), ("one.", 1), ("One. Two", 2), ("One. Two.", 2),
            ("Version 16.2 is out.", 1), ("Really?! Yes.", 2), ("One!  Two?  Three...", 3),
            ("line one\nline two.", 1),
        ]
    )
    func sentenceCount(text: String, expected: Int) {
        #expect(TerminalStopRule.sentenceCount(text) == expected)
    }
}
