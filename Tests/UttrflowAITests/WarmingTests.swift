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
    @Test("the generative transformer hands its model the instructions every request carries")
    func generativeWarmsWithInstructions() async {
        let model = FakeCleanupModel()
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await sut.warm()

        #expect(model.warmed == [CleanupPrompt.current.instructions])
    }

    @Test("the router warms every engine on its route and none off it")
    func routerWarmsTheRoute() async {
        let first = FakeTextTransformationEngine(kind: .foundationModels)
        let floor = FakeTextTransformationEngine(kind: .rules)
        let unused = FakeTextTransformationEngine(kind: .cloud)
        let router = TransformerRouter(
            engines: [first, floor, unused], preference: [.foundationModels, .rules])

        await router.warm()

        #expect(await first.warmCalls.count == 1)
        #expect(await floor.warmCalls.count == 1)
        #expect(await unused.warmCalls.isEmpty)
    }

    @Test("a model with nothing to prepare can still be asked")
    func coldModelIsHarmless() async {
        await ColdModel().warm(instructions: "anything")
    }
}
