import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("Added mark check")
struct AddedMarkCheckTests {
    @Test(
        "a mark the model added where the clause runs on is taken out and every word kept",
        arguments: [
            ("i want to go to the shop", "I want to go to. The shop.", "I want to go to the shop."),
            ("send it to the team", "Send it to the. Team.", "Send it to the team."),
            ("pick up milk and bread", "Pick up milk and: bread.", "Pick up milk and bread."),
            ("this is because of rain", "This is because? Of rain.", "This is because of rain."),
            ("call my sister today", "Call my! Sister today.", "Call my sister today."),
            ("ask Dr. Rao first", "Ask Dr.: Rao first.", "Ask Dr. Rao first."),
        ])
    func illegalMarkRemoved(input: String, rewritten: String, expected: String) {
        let result = AddedMarkCheck.checked(rewritten, against: input)
        #expect(result.text == expected)
        #expect(result.removed.count == 1)
    }

    @Test("a mark the recogniser wrote is never taken out here")
    func recogniserMarkKept() {
        let input = "I went to. The shop was shut"
        #expect(AddedMarkCheck.checked("I went to. The shop was shut.", against: input).removed.isEmpty)
    }

    @Test(
        "a rewrite with only legal marks is left as it is",
        arguments: [
            ("well i think so yes", "Well, I think so, yes."),
            ("who did you talk to", "Who did you talk to?"),
            ("meet at 5 then lunch", "Meet at 5. Then lunch."),
            ("notes\nthe plan", "Notes:\nThe plan."),
        ])
    func legalMarksKept(input: String, rewritten: String) {
        #expect(AddedMarkCheck.checked(rewritten, against: input).text == rewritten)
    }

    @Test(
        "a stop the model added before a subordinate clause with no main clause of its own is taken out",
        arguments: [
            (
                "i will call you tomorrow at ten am if that works for you",
                "I will call you tomorrow at 10 am. If that works for you.",
                "I will call you tomorrow at 10 am if that works for you."
            ),
            (
                "we can start the review now if everyone is here",
                "We can start the review now. If everyone is here.",
                "We can start the review now if everyone is here."
            ),
            (
                "i stayed home because it was raining",
                "I stayed home. Because it was raining.",
                "I stayed home because it was raining."
            ),
            (
                "send the draft when you are ready",
                "Send the draft. When you are ready.",
                "Send the draft when you are ready."
            ),
        ])
    func dependentFragmentJoined(input: String, rewritten: String, expected: String) {
        #expect(AddedMarkCheck.checked(rewritten, against: input).text == expected)
    }

    @Test(
        "a stop before a subordinate clause that carries its own main clause or asks a question stays",
        arguments: [
            ("i am free if it rains we stay in", "I am free. If it rains, we stay in."),
            ("i am free when will you come", "I am free. When will you come?"),
        ])
    func completeSentenceKept(input: String, rewritten: String) {
        #expect(AddedMarkCheck.checked(rewritten, against: input).text == rewritten)
    }

    @Test("the removal names the table row that refused it")
    func removalNamesRow() {
        let removed = AddedMarkCheck.checked("Go to the. Shop.", against: "go to the shop").removed
        #expect(removed == [.init(word: "the", mark: ".", state: .leadsOn)])
    }

    @Test("the transformer keeps the model's rewrite and drops only its illegal mark")
    func transformerDropsOnlyTheMark() async throws {
        let model = FakeCleanupModel { _ in "Well, I want to go to. The shop. Do you need a projector?" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let request = TransformationRequest(
            transcription: .fixture(
                text: "well i want to go to the shop do you need a projector", language: .english))
        #expect(
            try await sut.transform(request).text
                == "Well, I want to go to the shop. Do you need a projector?")
    }
}
