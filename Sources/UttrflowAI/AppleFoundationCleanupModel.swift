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
    /// Zero temperature keeps the model tidying rather than composing.
    private static let options = GenerationOptions(temperature: 0.0)

    /// One session made ahead of its request when the pipeline warms, shared by every copy of this value.
    private static let warmed = WarmSupply<LanguageModelSession> { instructions in
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        return session
    }

    /// Makes a model; every copy shares the warmed session.
    public init() {}

    /// Makes the next utterance's session now so its instructions load. See Docs/early-transcription.md.
    public func warm(instructions: String) async {
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
        guard await Self.fitsContext(text, instructions: instructions) else {
            throw .transformFailed(kind: kind, failure: .contextTooLarge)
        }
        do {
            let response = try await session.respond(
                to: text, generating: CleanedDictation.self, options: Self.options
            )
            return response.content.text
        } catch {
            throw .transformFailed(kind: kind, failure: .ofSystemModel(error))
        }
    }

    /// Counts both sides of the exchange before sending it, leaving room for the generated structure.
    private static func fitsContext(_ prompt: String, instructions: String) async -> Bool {
        let model = SystemLanguageModel.default
        let counts: (instructions: Int, prompt: Int, schema: Int, output: Int)
        if #available(macOS 26.4, *) {
            do {
                let promptTokens = try await model.tokenCount(for: Prompt(prompt))
                counts = (
                    try await model.tokenCount(for: Instructions(instructions)), promptTokens,
                    try await model.tokenCount(for: CleanedDictation.generationSchema), promptTokens
                )
            } catch {
                counts = estimatedCounts(prompt, instructions: instructions)
            }
        } else {
            counts = estimatedCounts(prompt, instructions: instructions)
        }
        return FoundationModelRequestBudget.fits(
            contextSize: model.contextSize, instructions: counts.instructions, prompt: counts.prompt,
            schema: counts.schema, expectedOutput: counts.output)
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
