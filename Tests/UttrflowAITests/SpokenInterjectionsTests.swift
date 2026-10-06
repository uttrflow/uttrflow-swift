import Testing

@testable import UttrflowAI
@testable import UttrflowCore

@Suite("Spoken interjections", .bug(id: 2261))
struct SpokenInterjectionsTests {
    private let examples: [(spoken: String, retained: String)] = [
        ("uh huh", "uh-huh"),
        ("uh huh sounds good", "uh-huh sounds good"),
        ("uh oh", "uh-oh"),
        ("mm hmm", "mm-hmm"),
        ("mhm", "mhm"),
        ("hmm", "hmm"),
        ("um, uh, I think so", "I think so"),
        ("uh-huh", "uh-huh"),
        ("mm-hmm", "mm-hmm"),
    ]

    @Test("keeps or joins each reply in both engines and every destination")
    func repliesSurviveEveryEngineAndDestination() async throws {
        for destination in Destination.allCases {
            for example in examples {
                let request = Self.request(example.spoken, destination: destination)
                let rules = try await RuleBasedTransformer().transform(request).text
                let model = FakeCleanupModel { Self.spokenText(in: $0) }
                let generative = try await GenerativeTextTransformer(
                    kind: .foundationModels, model: model
                ).transform(request).text

                #expect(rules.lowercased().contains(example.retained.lowercased()))
                #expect(generative == rules)
                // A reply the rules settle never reaches the model; one that does reach it carries the retained form.
                #expect(
                    model.calls.allSatisfy { $0.text.lowercased().contains(example.retained.lowercased()) })
            }
        }
    }

    private static func request(_ text: String, destination: Destination) -> TransformationRequest {
        let app = AppContext()
        return TransformationRequest(
            transcription: .fixture(text: text, language: .english),
            context: app,
            situation: Situation(app: app, insertion: app.insertionPoint, destination: destination))
    }

    private static func spokenText(in prompt: String) -> String {
        guard let line = prompt.split(separator: "\n").last,
            let spoken = line.range(of: "Spoken: \"")
        else { return prompt }
        return String(line[spoken.upperBound...].dropLast())
    }
}
