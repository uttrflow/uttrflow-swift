import Testing

@testable import UttrflowAI

/// Labels and quotes stripped from a single-line reply.
@Suite("ResponseUnwrapper")
struct ResponseUnwrapperTests {
    /// Unwraps with a default spoken text.
    private func unwrap(_ rewritten: String, spoken: String = "hello there") -> String {
        ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
    }

    /// What a local model produces: right words, wrong packaging, and a score of zero without this.
    @Test(
        "removes the label a model echoes from the worked examples",
        arguments: [
            "Cleaned: Hello there.",
            "Cleaned: \"Hello there.\"",
            "cleaned: Hello there.",
            "Output: Hello there.",
            "Result: \"Hello there.\"",
            "Corrected: Hello there.",
        ]
    )
    func removesLabel(produced: String) {
        #expect(unwrap(produced) == "Hello there.")
    }

    @Test(
        "removes quotes wrapped around the whole answer",
        arguments: [
            "\"Hello there.\"", "\u{201C}Hello there.\u{201D}", "'Hello there.'", "  \"Hello there.\"  ",
        ]
    )
    func removesSurroundingQuotes(produced: String) {
        #expect(unwrap(produced) == "Hello there.")
    }

    /// The speaker's own quotation marks are theirs to keep.
    @Test("keeps quotes that are part of what was said")
    func keepsInnerQuotes() {
        #expect(unwrap("He said \"hello\" to me.") == "He said \"hello\" to me.")
        #expect(unwrap("\"hello\" and \"goodbye\"") == "\"hello\" and \"goodbye\"")
    }

    /// The recogniser reports reported speech in quotes, and deleting them is a change to the sentence.
    @Test(
        "keeps the quotes when the speaker's own words are the quotation",
        arguments: [
            ("\"We ship on Friday.\"", "\"we ship on friday\""),
            ("\u{201C}We ship on Friday.\u{201D}", "\"we ship on friday\""),
            // The pair need not be the same one: a model that answered in curly quotes still added nothing.
            ("\u{201C}We ship on Friday.\u{201D}", "\u{201C}we ship on friday\u{201D}"),
            ("'We ship on Friday.'", "'we ship on friday'"),
        ]
    )
    func keepsAQuotationTheSpeakerSaid(produced: String, spoken: String) {
        #expect(unwrap(produced, spoken: spoken) == produced)
    }

    /// The label is still the model's, even inside a quotation the speaker did say.
    @Test("takes the label off a quotation the speaker said")
    func stripsALabelAroundASpokenQuotation() {
        #expect(
            unwrap("Cleaned: \"We ship on Friday.\"", spoken: "\"we ship on friday\"")
                == "\"We ship on Friday.\"")
    }

    @Test("still removes the model's own quotes when the draft carries none")
    func stillStripsTheModelsOwnQuotes() {
        #expect(unwrap("\"We ship on Friday.\"", spoken: "we ship on friday") == "We ship on Friday.")
    }

    /// A sentence is the model chatting, not a label, and the guard should still catch it.
    @Test(
        "leaves conversational preambles alone, so the guard still rejects them",
        arguments: [
            "Sure, here is the text: Hello there.",
            "Here is the cleaned version: Hello there.",
            "I've corrected it: Hello there.",
        ]
    )
    func leavesPreamblesForTheGuard(produced: String) {
        #expect(unwrap(produced) == produced)
    }

    /// Dictating "Output: ship it" must survive.
    @Test("keeps a label the speaker said themselves")
    func keepsSpeakersOwnLabel() {
        #expect(unwrap("Output: ship it.", spoken: "output ship it") == "Output: ship it.")
        #expect(unwrap("Result: 42.", spoken: "result 42") == "Result: 42.")
    }

    @Test("leaves ordinary text untouched")
    func leavesOrdinaryTextAlone() {
        #expect(unwrap("Hello there.") == "Hello there.")
        #expect(unwrap("Meet me at 3:30.") == "Meet me at 3:30.")
        #expect(unwrap("") == "")
    }

    @Test("removes a label and its quotes together")
    func removesBoth() {
        #expect(unwrap("  Cleaned:  \"Hello there.\"  ") == "Hello there.")
    }

    @Test("leaves a colon that is not a label")
    func nonLabelColon() {
        #expect(unwrap("John: I'll be late.") == "John: I'll be late.")
    }
}

/// Replies that echo the prompt back before answering.
@Suite("Unwrapping a replayed exchange")
struct ReplayedExchangeTests {
    /// What a 4B model produces: the prompt echoed back, then its answer.
    @Test("takes the answer from a reply that echoed the whole exchange")
    func takesTheLastLabelledLine() {
        let produced = """
            Spoken: "hey sarah just checking in on the the design review"
            Cleaned: "Hey Sarah, just checking in on the design review."
            """
        #expect(
            ResponseUnwrapper.unwrap(produced, spoken: "hey sarah just checking in")
                == "Hey Sarah, just checking in on the design review."
        )
    }

    @Test("takes the last answer when a model replays several examples")
    func takesTheLastOfMany() {
        let produced = """
            Spoken: "one"
            Cleaned: "One."
            Spoken: "two"
            Cleaned: "Two."
            """
        #expect(ResponseUnwrapper.unwrap(produced, spoken: "two") == "Two.")
    }

    /// A speaker who dictates several lines must keep all of them.
    @Test("keeps every line when none of them is a label")
    func keepsUnlabelledMultilineText() {
        let produced = "First line.\nSecond line."
        #expect(ResponseUnwrapper.unwrap(produced, spoken: "first line second line") == produced)
    }

    @Test("keeps the lines after the answer's own label")
    func keepsContinuationAfterTheLabel() {
        let produced = "Cleaned: \"First line.\"\nStill part of the answer."
        #expect(
            ResponseUnwrapper.unwrap(produced, spoken: "first line still part")
                == "\"First line.\" Still part of the answer."
        )
    }
}
