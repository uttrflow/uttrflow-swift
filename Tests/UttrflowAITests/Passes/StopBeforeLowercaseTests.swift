import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// A stop the recogniser wrote stays when the next word was heard in lowercase and nothing else shows the sentence carrying on.
@Suite("Stop before a lowercase word", .bug(id: 3470))
struct StopBeforeLowercaseTests {
    private func clean(_ text: String) async throws -> String {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .plain)
        let request = TransformationRequest(
            transcription: .fixture(text: text, language: .english), situation: situation)
        return try await RuleBasedTransformer().transform(request).text
    }

    @Test(
        "keeps the stop the recogniser wrote and the word after it as it was heard",
        arguments: [
            ("We shipped it. eBay is next", "We shipped it. eBay is next."),
            ("Please send it today. i will check tomorrow", "Please send it today. I will check tomorrow."),
            ("The patient is stable. vitals are normal", "The patient is stable. Vitals are normal."),
            ("The price is five dollars. that is cheap", "The price is 5 dollars. That is cheap."),
            ("He is here. she is not", "He is here. She is not."),
            ("Yes. no. maybe", "Yes. No. Maybe."),
            ("Dr. Smith is here", "Dr. Smith is here."),
        ]
    )
    func keepsTheStop(spoken: String, expected: String) async throws {
        #expect(try await clean(spoken) == expected)
    }
}
