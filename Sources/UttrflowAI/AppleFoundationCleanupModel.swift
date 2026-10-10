// Apple's on-device language model as a cleanup model, with the structured shape it fills in.
public import UttrflowCore
import FoundationModels

/// The shape the model fills in; a structured value stops the "Sure, here is the text:" prefix.
@available(macOS 26, *)
@Generable
struct CleanedDictation {
    /// The tidied dictation.
    @Guide(description: PromptContract.answerGuide)
    var text: String
}

/// Apple's on-device model; only the real model can exercise it, so it sits outside the coverage gate.
@available(macOS 26, *)
public struct AppleFoundationCleanupModel: CleanupModel {
    /// Greedy sampling keeps the model tidying rather than composing; the ceiling stops a runaway answer early.
    private static func options(responseCeiling: Int) -> GenerationOptions {
        GenerationOptions(sampling: .greedy, maximumResponseTokens: responseCeiling)
    }

    /// One session made ahead of its request when the pipeline warms, shared by every copy of this value.
    private static let warmed = WarmSupply<LanguageModelSession> { instructions in
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        return session
    }

    /// The instructions' token count, kept from the warm so the request does not wait on it.
    private static let instructionCounts = TokenCountMemo()

    /// The answer shape's token count, which never changes within a run.
    private static let schemaCounts = TokenCountMemo()

    /// Makes a model; every copy shares the warmed session.
    public init() {}

    /// Makes the next utterance's session now so its instructions load. See Docs/early-transcription.md.
    public func warm(instructions: String) async {
        // Counted before the prewarm, since a tokenizer call after it discards the warm.
        if #available(macOS 26.4, *) {
            _ = try? await Self.instructionTokens(instructions)
            _ = try? await Self.schemaTokens()
        }
        await Self.warmed.replenish(for: instructions)
    }

    /// Available unless Apple's model is off, Apple does not declare the language, or it is withheld.
    public func availability(for language: LanguageCode?) async -> TransformerAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .unavailable(reason: .appleIntelligenceDisabled)
            case .modelNotReady: return .unavailable(reason: .modelNotReady)
            case .deviceNotEligible: return .unavailable(reason: .deviceNotEligible)
            @unknown default: return .unavailable(reason: .other(String(describing: reason)))
            }
        @unknown default:
            return .unavailable(reason: .other("unrecognised availability"))
        }

        guard let language else { return .available }
        let declared = SystemLanguageModel.default.supportedLanguages
            .contains { $0.languageCode.map { LanguageCode($0.identifier) } == language }
        return AppleModelLanguages.availability(of: language, declaredByApple: declared)
    }

    /// Rewrites one utterance as a structured value, in the warmed session or a fresh one.
    public func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        // A fresh session per utterance, so one sentence's context cannot bleed into the next.
        let session =
            await Self.warmed.take(for: instructions) ?? LanguageModelSession(instructions: instructions)
        guard let ceiling = await Self.responseCeiling(text, instructions: instructions) else {
            throw .transformFailed(kind: kind, failure: .contextTooLarge)
        }
        do {
            let response = try await session.respond(
                to: text, generating: CleanedDictation.self, options: Self.options(responseCeiling: ceiling)
            )
            return response.content.text
        } catch {
            throw .transformFailed(kind: kind, failure: .ofSystemModel(error))
        }
    }

    /// Counts both sides of the exchange before sending it; the answer's token ceiling when it fits, else nil.
    private static func responseCeiling(_ prompt: String, instructions: String) async -> Int? {
        let model = SystemLanguageModel.default
        let counts: (instructions: Int, prompt: Int, schema: Int, output: Int)
        if #available(macOS 26.4, *) {
            do {
                let instructionCount = try await instructionTokens(instructions)
                let schemaCount = try await schemaTokens()
                // Counting the words would discard the warm session, so the high estimate stands in whenever it fits.
                let estimate = FoundationModelRequestBudget.estimatedPromptTokens(
                    prompt, contextSize: model.contextSize, instructions: instructionCount,
                    schema: schemaCount)
                let promptTokens: Int
                if let estimate {
                    promptTokens = estimate
                } else {
                    promptTokens = try await model.tokenCount(for: Prompt(prompt))
                }
                counts = (instructionCount, promptTokens, schemaCount, promptTokens)
            } catch {
                counts = estimatedCounts(prompt, instructions: instructions)
            }
        } else {
            counts = estimatedCounts(prompt, instructions: instructions)
        }
        guard
            FoundationModelRequestBudget.fits(
                contextSize: model.contextSize, instructions: counts.instructions, prompt: counts.prompt,
                schema: counts.schema, expectedOutput: counts.output)
        else { return nil }
        return FoundationModelRequestBudget.responseCeiling(
            promptTokens: counts.prompt, schemaTokens: counts.schema)
    }

    /// The instructions' token count, counted once per distinct instructions.
    @available(macOS 26.4, *)
    private static func instructionTokens(_ instructions: String) async throws -> Int {
        try await instructionCounts.tokens(for: instructions) { text in
            try await SystemLanguageModel.default.tokenCount(for: Instructions(text))
        }
    }

    /// The answer shape's token count, counted once.
    @available(macOS 26.4, *)
    private static func schemaTokens() async throws -> Int {
        try await schemaCounts.tokens(for: "CleanedDictation") { _ in
            try await SystemLanguageModel.default.tokenCount(for: CleanedDictation.generationSchema)
        }
    }

    /// Older OS releases lack the tokenizer API, so estimate ASCII high and count every other scalar individually.
    private static func estimatedCounts(
        _ prompt: String, instructions: String
    ) -> (instructions: Int, prompt: Int, schema: Int, output: Int) {
        let promptTokens = FoundationModelRequestBudget.estimatedTokens(in: prompt)
        return (
            FoundationModelRequestBudget.estimatedTokens(in: instructions), promptTokens,
            128, promptTokens
        )
    }
}
