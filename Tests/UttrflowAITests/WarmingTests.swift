import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// A model with nothing of its own to prepare.
private struct ColdModel: CleanupModel {
    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }
    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        text
    }
}

/// What `warm()` reaches through the transformer and the router.
@Suite("Warming the tidier ahead of a dictation")
struct WarmingTests {
    @Test("the generative transformer hands its model the instructions for where the words are going")
    func generativeWarmsForTheDestination() async {
        let model = FakeCleanupModel()
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await sut.warm(for: Situation(app: .unknown, insertion: .unknown, destination: .messaging))

        #expect(model.warmed == [PromptBuilder.standard.instructions(for: .messaging)])
        #expect(model.warmed != [PromptBuilder.standard.instructions(for: .plain)])
    }

    @Test("with nowhere known, the generative transformer warms for plain text")
    func generativeWarmsForPlainByDefault() async {
        let model = FakeCleanupModel()
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await sut.warm(for: nil)

        #expect(model.warmed == [PromptBuilder.standard.instructions(for: .plain)])
    }

    @Test("the router warms every engine on its route for the same place, and none off it")
    func routerWarmsTheRoute() async {
        let first = FakeTextTransformationEngine(kind: .foundationModels)
        let floor = FakeTextTransformationEngine(kind: .rules)
        let unused = FakeTextTransformationEngine(kind: .cloud)
        let router = TransformerRouter(
            engines: [first, floor, unused], preference: [.foundationModels, .rules])
        let situation = Situation(app: .fixture(), insertion: .unknown, destination: .messaging)

        await router.warm(for: situation)

        #expect(await first.warmCalls.events == [situation])
        #expect(await floor.warmCalls.events == [situation])
        #expect(await unused.warmCalls.isEmpty)
    }

    @Test("a model with nothing to prepare can still be asked")
    func coldModelIsHarmless() async {
        await ColdModel().warm(instructions: "anything")
    }
}
