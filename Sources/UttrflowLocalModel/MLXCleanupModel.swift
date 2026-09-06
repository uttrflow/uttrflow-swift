public import UttrflowAI
public import UttrflowCore
// The MLX macros expand to code naming these types, so the imports cannot be private.
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

// A local open-weight model behind the same clean-up boundary as Apple's, built with `make bakeoff`.
/// Runs an open-weight model on the Mac's GPU, which is where Hindi clean-up comes from.
public actor MLXCleanupModel: CleanupModel {
    /// Which weights run.
    private let model: LocalModel
    /// The most tokens one rewrite may produce.
    private let maximumTokens: Int
    /// The loaded weights, absent until ``prepare(onProgress:)`` has run.
    private var container: ModelContainer?

    /// Names the model to run, without loading anything yet.
    public init(model: LocalModel, maximumTokens: Int = 256) {
        self.model = model
        self.maximumTokens = maximumTokens
    }

    /// Downloads and loads the weights, so the cost is paid deliberately and not inside a dictation.
    public func prepare(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws(TransformationError) {
        guard container == nil else { return }
        do {
            container = try await loadModelContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: ModelConfiguration(id: model.identifier),
                progressHandler: { onProgress($0.fractionCompleted) }
            )
        } catch {
            throw .transformFailed(kind: .localModel, description: error.localizedDescription)
        }
    }

    /// Whether this model is loaded and can work in `language`.
    public func availability(for language: LanguageCode?) async -> TransformerAvailability {
        guard container != nil else { return .unavailable(reason: "the local model is not loaded") }
        guard let language else { return .available }
        return model.supports(language) ? .available : .unsupportedLanguage(language)
    }

    /// Rewrites `text` under `instructions`, loading the weights first if they are not yet there.
    public func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        try await prepare()
        guard let container else {
            throw .transformFailed(kind: kind, description: "the local model did not load")
        }

        do {
            // A fresh session per utterance, so one sentence cannot bleed into the next.
            let session = ChatSession(
                container,
                instructions: instructions,
                generateParameters: GenerateParameters(
                    maxTokens: maximumTokens, temperature: 0
                )
            )
            return try await session.respond(to: text)
        } catch {
            throw .transformFailed(kind: kind, description: error.localizedDescription)
        }
    }
}
