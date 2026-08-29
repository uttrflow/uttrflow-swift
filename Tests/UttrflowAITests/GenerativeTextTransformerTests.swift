import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("GenerativeTextTransformer")
struct GenerativeTextTransformerTests {
    private func request(_ text: String, language: LanguageCode? = .english) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: language))
    }

    @Test("reports the engine it stands for", arguments: [TransformerKind.foundationModels, .cloud])
    func kind(kind: TransformerKind) {
        let sut = GenerativeTextTransformer(kind: kind, model: FakeCleanupModel())
        #expect(sut.kind == kind)
    }

    @Test("asks the model whether it knows the spoken language")
    func asksAboutLanguage() async {
        let model = FakeCleanupModel()
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        _ = await sut.availability(for: request("hello", language: .hindi))
        #expect(model.languagesAsked == [.hindi])
    }

    @Test("passes the model's own verdict straight through")
    func reportsModelAvailability() async {
        let model = FakeCleanupModel(availability: .unsupportedLanguage(.hindi))
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        #expect(await sut.availability(for: request("hello")) == .unsupportedLanguage(.hindi))
    }

    @Test("sends the prompt's instructions, not something improvised")
    func sendsPromptInstructions() async throws {
        let model = FakeCleanupModel { _ in "Hello there." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        _ = try await sut.transform(request("hello there"))

        #expect(model.calls.first?.instructions == CleanupPrompt.current.instructions)
        #expect(model.calls.first?.text == "Spoken: \"hello there\"")
        #expect(model.calls.first?.kind == .foundationModels)
    }

    @Test("attributes the result to itself")
    func attributesResult() async throws {
        let model = FakeCleanupModel { _ in "Hello there." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        let result = try await sut.transform(request("hello there"))
        #expect(result == TransformationResult(text: "Hello there.", producedBy: .foundationModels))
    }

    /// The model leaves output ragged even when told not to, so a deterministic pass
    /// finishes it.
    @Test(
        "finishes what the model left ragged",
        arguments: [
            ("Hello  there", "Hello there."),
            ("Hello there", "Hello there."),
            ("  Hello there.  ", "Hello there."),
        ]
    )
    func tidiesModelOutput(modelOutput: String, expected: String) async throws {
        let model = FakeCleanupModel { _ in modelOutput }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        #expect(try await sut.transform(request("hello there")).text == expected)
    }

    @Test("refuses a rewrite that changed what the speaker meant")
    func rejectsChangedMeaning() async {
        let model = FakeCleanupModel { _ in "Paris" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await #expect(throws: TransformationError.self) {
            try await sut.transform(request("what is the capital of france"))
        }
    }

    @Test("says why it refused, so a failure can be understood")
    func explainsRejection() async {
        let model = FakeCleanupModel { _ in "Here is the text: hello" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        do {
            _ = try await sut.transform(request("hello there my friend"))
            Issue.record("expected the rewrite to be refused")
        } catch {
            guard case .outputRejected(let reason) = error else {
                Issue.record("expected outputRejected, got \(error)")
                return
            }
            #expect(reason.contains("here is"))
        }
    }

    @Test("surfaces a model failure rather than returning the raw transcript silently")
    func surfacesModelFailure() async {
        let model = FakeCleanupModel()
        model.fail(with: .transformFailed(kind: .foundationModels, description: "busy"))
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await #expect(throws: TransformationError.self) { try await sut.transform(request("hello")) }
    }
}

@Suite("RuleBasedTransformer")
struct RuleBasedTransformerTests {
    private let sut = RuleBasedTransformer()

    private func request(_ text: String, language: LanguageCode? = .english) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: language))
    }

    /// Everything above it may refuse; this is the floor, so it cannot.
    @Test(
        "is available for anything, including languages no model knows",
        arguments: [LanguageCode.english, .hindi, LanguageCode("ja") ?? .english]
    )
    func alwaysAvailable(language: LanguageCode) async {
        #expect(await sut.availability(for: request("hello", language: language)) == .available)
    }

    @Test("is available even when no language was detected")
    func availableWithoutLanguage() async {
        let request = TransformationRequest(transcription: Transcription(text: "hello"))
        #expect(await sut.availability(for: request) == .available)
    }

    @Test(
        "does everything it can without a model",
        arguments: [
            ("um hello   there", "Hello there."),
            ("uh i think so", "I think so."),
            ("the the deployment is running", "The deployment is running."),
            ("hello. um there", "Hello. There."),
        ]
    )
    func tidies(input: String, expected: String) async throws {
        #expect(try await sut.transform(request(input)).text == expected)
    }

    @Test("attributes its work to itself")
    func attributesResult() async throws {
        #expect(try await sut.transform(request("hello")).producedBy == .rules)
    }

    @Test("cannot invent anything, whatever it is given")
    func neverInvents() async throws {
        let result = try await sut.transform(request("नमस्ते मैं आज आऊंगा"))
        #expect(result.text.contains("नमस्ते"))
    }
}
