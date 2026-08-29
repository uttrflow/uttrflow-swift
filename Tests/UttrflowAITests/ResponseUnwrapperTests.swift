import Testing

@testable import UttrflowAI

@Suite("ResponseUnwrapper")
struct ResponseUnwrapperTests {
    private func unwrap(_ rewritten: String, spoken: String = "hello there") -> String {
        ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
    }

    /// Exactly what a local model produced the first time it was measured. The words
    /// were right; only the packaging was wrong, and it scored zero.
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

@Suite("Unwrapping a replayed exchange")
struct ReplayedExchangeTests {
    /// Exactly what a 4B model produced: the prompt echoed back, then its answer.
    /// Its words were right; only the replay made the score look terrible.
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
