import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// A chat field, which reads as prose.
private func chat() -> GenerationSituation {
    GenerationSituation(application: "Chat", field: "Message", isMultiline: true)
}

@Suite("A prose line never ends inside a bracket, a quote or a phrase")
struct DanglingEndTests {
    @Test(
        "An open ending is cut back to the last complete phrase.",
        arguments: [
            ("He walked into the ", "He walked into the room and (", "He walked into the room"),
            ("She said ", "She said hello and \"", "She said hello"),
            ("We can meet ", "We can meet later -", "We can meet later"),
            ("I will bring ", "I will bring snacks and", "I will bring snacks"),
            ("Let me check ", "Let me check the logs and the", "Let me check the logs"),
            ("Thanks for ", "Thanks for the update or", "Thanks for the update"),
            ("Let me ask ", "Let me ask Sam and my", "Let me ask Sam"),
        ]
    )
    func cutsBack(typed: String, line: String, expected: String) {
        #expect(CompletionText.finished([line], typed: typed, in: chat()) == [expected])
    }

    @Test("A line with nothing left past the typed text is refused.")
    func refusesWhenNothingIsLeft() {
        #expect(
            CompletionText.finished(["He walked into the ("], typed: "He walked into the ", in: chat())
                .isEmpty)
    }

    @Test(
        "A finished line is kept as it is.",
        arguments: [
            "See you at the meeting tomorrow", "She said \"hello\"", "We use the well-known tool",
            "I'm so sorry about that", "We need those", "Do you want some", "I'll take both",
        ]
    )
    func keepsFinished(line: String) {
        #expect(CompletionText.finished([line], typed: String(line.prefix(4)), in: chat()) == [line])
    }
}
