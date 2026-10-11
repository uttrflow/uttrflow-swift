public import UttrflowAI
public import UttrflowCore

/// The same loaded weights tidy dictation, so the app holds one copy of the model for suggestions and clean-up.
extension MLXCandidateScorer: CleanupModel {
    /// Available only while the weights are loaded; a dictation never waits on a load.
    public func availability(for language: LanguageCode?) async -> TransformerAvailability {
        guard container != nil else { return .unavailable(reason: .other("the local model is not loaded")) }
        guard let language else { return .available }
        return model.supports(language) ? .available : .unsupportedLanguage(language)
    }

    /// One block of instructions, with no examples apart from it.
    public func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        try await tidy(text, system: instructions, examples: [], kind: kind)
    }

    /// The rules as the system turn and each worked example as an earlier exchange, so the model answers rather than reads on.
    public func rewrite(
        _ text: String, prompt: ModelPrompt, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        try await tidy(text, system: prompt.rules, examples: prompt.examples, kind: kind)
    }
}
