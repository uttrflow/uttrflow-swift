// Reproduces #2436: the on-device model returns text byte-identical to its input and the answer is accepted, so only the rules engine adds the formatting it should always have added.
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// Issue 2436: the on-device model's pass-through is rejected and the rules engine takes over.
@Suite("A model's byte-identical echo is rejected", .bug(id: 2436))
struct ModelEchoRejectionTests {
    private func request(_ text: String) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: .english))
    }

    /// The shipped reproduction: the model echoes the input and the rules engine does the work.
    @Test("the on-device model hands back its input unchanged")
    func foundationModelEchoesInput() async {
        let model = FakeCleanupModel { _ in "one on one with rahul do you need a projector" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await #expect(throws: TransformationError.self) {
            try await sut.transform(request("one on one with rahul do you need a projector"))
        }
    }

    /// The smaller local-model path that Hindi dictation reaches does the same when the model echo is identical.
    @Test("the smaller local-model path rejects its own byte-identical echo")
    func localModelEchoesInput() async {
        let model = FakeCleanupModel { _ in "review sprint goals before planning do you need a projector" }
        let sut = GenerativeTextTransformer(kind: .localModel, model: model)

        await #expect(throws: TransformationError.self) {
            try await sut.transform(request("review sprint goals before planning do you need a projector"))
        }
    }

    /// A short reply the rules can answer is held back by the on-device model today, so the rejection only fires when the rules need to do real work.
    @Test("a short reply is not refused even when the model happens to echo it")
    func shortReplyIsNotRefused() async throws {
        let model = FakeCleanupModel { _ in "hello there" }
        let generative = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let router = TransformerRouter(
            engines: [generative, RuleBasedTransformer()],
            preference: [.foundationModels, .rules])

        let result = try await router.transform(request("hello there"))

        #expect(result.text == "Hello there.")
        #expect(result.cleaning?.refusals.isEmpty != false)
    }

    /// The composed answer must not be attributed to the model when only the rules formatted it.
    @Test("the model-attributed answer is not marked foundation when only the rules formatted it")
    func rulesEngineNotModel() async throws {
        let model = FakeCleanupModel { _ in "review sprint goals before planning" }
        let generative = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let router = TransformerRouter(
            engines: [generative, RuleBasedTransformer()],
            preference: [.foundationModels, .rules])

        let result = try await router.transform(request("review sprint goals before planning"))

        #expect(result.producedBy == .rules)
        #expect(result.text == "Review sprint goals before planning.")
    }

    /// The unwrapper strips the worked-example label the model wraps the echo in; the guard still rejects.
    @Test("a labelled echo is still a byte-identical echo")
    func labelledEchoIsRejected() async {
        let model = FakeCleanupModel { _ in "Cleaned: one on one with rahul do you need a projector" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await #expect(throws: TransformationError.self) {
            try await sut.transform(request("one on one with rahul do you need a projector"))
        }
    }

    /// A dictation that already has a capital and a stop is left alone: the model did not need to do anything.
    @Test("a dictation that already carries a capital and a stop is accepted as the model's echo")
    func alreadyFormattedIsAccepted() async throws {
        let model = FakeCleanupModel { _ in "Hello there." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        let result = try await sut.transform(request("Hello there."))

        #expect(result.text == "Hello there.")
        #expect(result.producedBy == .foundationModels)
    }

    /// A short, single-word echo is not a refusal: a single word dictation carries nothing for the rules to do either.
    @Test("a single-word echo is not refused")
    func singleWordEchoIsAccepted() async throws {
        let model = FakeCleanupModel { _ in "yes" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        let result = try await sut.transform(request("yes"))

        #expect(result.text == "Yes.")
    }

    /// The plain prompt block now carries the worked examples the model needs to see sentence-casing and a name.
    @Test("the plain prompt block carries two worked examples")
    func plainBlockHasWorkedExamples() {
        let plain = PromptBlocks.standard[PromptBlockID(rawValue: "plain")]
        #expect(plain != nil)
        #expect(plain?.examples.count ?? 0 >= 2)
    }
}
