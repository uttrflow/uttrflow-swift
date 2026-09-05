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

    /// The passes run first, so the model never sees the fillers and discarded halves it might rewrite.
    @Test("hands the model the draft after the passes, not the raw words")
    func handsModelTheDraft() async throws {
        let model = FakeCleanupModel { _ in "Let's meet at five." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        _ = try await sut.transform(request("um let's meet at four no sorry at five"))

        #expect(model.calls.first?.text == "Spoken: \"let's meet at five\"")
    }

    @Test("leaves casing and the full stop to the model, and finishes what it forgets")
    func leavesFinishingToTheModel() async throws {
        let model = FakeCleanupModel { _ in "hello there" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        #expect(try await sut.transform(request("um hello there")).text == "hello there.")
    }

    @Test("does not count a pass's removals against the model")
    func judgesAgainstTheDraft() async throws {
        let model = FakeCleanupModel { _ in "Yes, please." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        let result = try await sut.transform(request("um uh er hmm um uh er hmm yes please"))
        #expect(result.text == "Yes, please.")
    }

    @Test("runs whatever pipeline it is given before the model")
    func usesGivenPipeline() async throws {
        let model = FakeCleanupModel { _ in "Um, hello there." }
        let sut = GenerativeTextTransformer(
            kind: .foundationModels, model: model, pipeline: CleaningPipeline(passes: []))

        _ = try await sut.transform(request("um hello there"))
        #expect(model.calls.first?.text == "Spoken: \"um hello there\"")
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
            ("let's meet at four no sorry at five", "Let's meet at five."),
            ("we're on postgres sixteen point two", "We're on postgres 16.2."),
            ("milk comma eggs comma and bread", "Milk, eggs, and bread."),
        ]
    )
    func tidies(input: String, expected: String) async throws {
        #expect(try await sut.transform(request(input)).text == expected)
    }

    @Test("runs whatever pipeline it is given")
    func usesGivenPipeline() async throws {
        let sut = RuleBasedTransformer(pipeline: CleaningPipeline(passes: [FillersPass()]))
        #expect(try await sut.transform(request("um hello there")).text == "hello there")
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
