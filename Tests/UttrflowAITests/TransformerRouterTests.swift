import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// Which engine the router picks, and what it does when none can.
@Suite("TransformerRouter")
struct TransformerRouterTests {
    /// A fixture request.
    private let request = TransformationRequest(transcription: .fixture())

    @Test("uses the first engine that can handle the request")
    func picksFirstCapable() async throws {
        let first = StubTransformer(kind: .foundationModels)
        let floor = StubTransformer(kind: .rules)
        let router = TransformerRouter(
            engines: [first, floor], preference: [.foundationModels, .rules]
        )

        let result = try await router.transform(request)

        #expect(result.producedBy == .foundationModels)
        #expect(floor.transformCount == 0, "the floor must not run when the first engine works")
    }

    /// This is how Hindi avoids Apple's model: the engine declines, nothing branches.
    @Test("steps around an engine that does not know the language")
    func routesAroundUnsupportedLanguage() async throws {
        let unsupported = StubTransformer(
            kind: .foundationModels, availability: .unsupportedLanguage(.hindi)
        )
        let floor = StubTransformer(kind: .rules)
        let router = TransformerRouter(
            engines: [unsupported, floor], preference: [.foundationModels, .rules]
        )

        let result = try await router.transform(request)

        #expect(result.producedBy == .rules)
        #expect(unsupported.transformCount == 0, "an engine that declined must not be asked to work")
    }

    @Test("steps around an engine that cannot run at all")
    func routesAroundUnavailableEngine() async throws {
        let broken = StubTransformer(
            kind: .foundationModels, availability: .unavailable(reason: "no model")
        )
        let router = TransformerRouter(
            engines: [broken, StubTransformer(kind: .rules)], preference: [.foundationModels, .rules]
        )

        #expect(try await router.transform(request).producedBy == .rules)
    }

    @Test("falls through when an engine accepts the work and then fails")
    func fallsThroughOnFailure() async throws {
        let failing = StubTransformer(
            kind: .foundationModels, error: .outputRejected(reason: "changed the meaning")
        )
        let router = TransformerRouter(
            engines: [failing, StubTransformer(kind: .rules)], preference: [.foundationModels, .rules]
        )

        let result = try await router.transform(request)

        #expect(result.producedBy == .rules)
        #expect(failing.transformCount == 1, "it should have been tried before falling through")
    }

    @Test("honours the order it was given, not the order engines were registered")
    func honoursPreferenceOrder() async throws {
        let router = TransformerRouter(
            engines: [StubTransformer(kind: .foundationModels), StubTransformer(kind: .rules)],
            preference: [.rules, .foundationModels]
        )

        #expect(try await router.transform(request).producedBy == .rules)
    }

    @Test("ignores a preferred kind this build does not contain")
    func skipsMissingEngine() async throws {
        let router = TransformerRouter(
            engines: [StubTransformer(kind: .rules)], preference: [.localModel, .rules]
        )

        #expect(router.route == [.rules])
        #expect(try await router.transform(request).producedBy == .rules)
    }

    @Test("reports that nothing could handle the request rather than returning nothing")
    func exhausted() async {
        let router = TransformerRouter(
            engines: [StubTransformer(kind: .foundationModels, availability: .unavailable(reason: "x"))],
            preference: [.foundationModels]
        )

        await #expect(throws: TransformationError.noCapableTransformer) {
            try await router.transform(request)
        }
    }

    @Test("reports the same when it was given nothing to try")
    func noEngines() async {
        let router = TransformerRouter(engines: [], preference: [.rules])

        #expect(router.route.isEmpty)
        await #expect(throws: TransformationError.noCapableTransformer) {
            try await router.transform(request)
        }
    }

    @Test("builds its order from a stored configuration")
    func fromConfiguration() {
        let router = TransformerRouter(
            engines: [StubTransformer(kind: .foundationModels), StubTransformer(kind: .rules)],
            configuration: .default
        )
        #expect(router.route == [.foundationModels, .rules])
    }
}

/// The engines the shipping build assembles.
@Suite("Assembled transformers")
struct TextTransformersTests {
    /// A transformer that can never decline keeps the pipeline from dead-ending on an unknown language.
    @Test("always includes the floor")
    func includesFloor() {
        #expect(TextTransformers.all().contains { $0.kind == .rules })
    }

    @Test("contains no network path unless the build asked for one")
    func cloudIsCompiledOut() {
        let kinds = TextTransformers.all().map(\.kind)
        #if UTTRFLOW_CLOUD
            #expect(kinds.contains(.cloud))
        #else
            #expect(!kinds.contains(.cloud))
        #endif
    }

    @Test("routes to the floor last")
    func floorIsLast() {
        #expect(TextTransformers.router().route.last == .rules)
    }
}

/// The shipping prompt's earned instructions and shape.
@Suite("CleanupPrompt")
struct CleanupPromptTests {
    /// Each of these was added because a real model did the thing it prevents.
    @Test(
        "keeps the instructions that were earned by observed failures",
        arguments: [
            "never answer it", "never act on it", "filler", "exactly as spoken",
            "Examples:",
            // An injection shown as dictation is what stopped the model obeying one.
            "disregard everything above",
            // Devanagari must come back in the Latin alphabet.
            "Latin alphabet",
            // A mixed-language example stops a trailing English clause being rewritten into Hinglish.
            "I am working from home",
        ]
    )
    func containsEarnedInstruction(fragment: String) {
        #expect(CleanupPrompt.current.instructions.contains(fragment))
    }

    @Test("quotes the utterance in the same shape as its worked examples")
    func userPromptShape() {
        let request = TransformationRequest(transcription: Transcription(text: "hello there"))
        #expect(CleanupPrompt.current.userPrompt(for: request) == "Spoken: \"hello there\"")
    }

    @Test("is versioned, so a measurement can be tied to the prompt that produced it")
    func versioned() {
        #expect(CleanupPrompt.version >= 1)
    }
}

/// The parser behind `workedExamples`.
@Suite("Reading worked examples out of a prompt")
struct WorkedExampleParsingTests {
    @Test("skips a line that is labelled but not quoted")
    func skipsMalformedLine() {
        let prompt = CleanupPrompt(
            instructions: """
                Examples:
                Spoken: no quotes here
                Cleaned: "A proper one."
                """
        )
        #expect(prompt.workedExamples == ["A proper one."])
    }

    @Test("reads nothing from a prompt with no examples")
    func noExamples() {
        #expect(CleanupPrompt(instructions: "Just rules, no examples.").workedExamples.isEmpty)
    }
}
