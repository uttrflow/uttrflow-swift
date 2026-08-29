public import UttrflowAI
public import UttrflowCore
// The MLX macros expand to code naming these types, so the imports cannot be private.
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs an open-weight model on the Mac's GPU.
///
/// Exists because Apple's on-device model has no Hindi. Slots in behind the same
/// ``CleanupModel`` boundary as Apple's, so it inherits the same prompt, the same
/// meaning checks and the same routing — the only difference is which weights run.
///
/// Excluded from the coverage gate: exercising it means downloading gigabytes and
/// running inference, which `uttrflow-dev bakeoff` does.
///
/// - Important: MLX compiles Metal shaders that Swift Package Manager's command line
///   cannot build, so anything linking this must be built with `xcodebuild`. See
///   `make bakeoff`.
public actor MLXCleanupModel: CleanupModel {
    private let model: LocalModel
    private let maximumTokens: Int
    private var container: ModelContainer?

    public init(model: LocalModel, maximumTokens: Int = 256) {
        self.model = model
        self.maximumTokens = maximumTokens
    }

    /// Downloads and loads the weights, reporting progress.
    ///
    /// Separate from ``rewrite(_:instructions:kind:)`` so a caller can pay the cost
    /// deliberately rather than inside a user's first dictation.
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

    public func availability(for language: LanguageCode?) async -> TransformerAvailability {
        guard container != nil else { return .unavailable(reason: "the local model is not loaded") }
        guard let language else { return .available }
        return model.supports(language) ? .available : .unsupportedLanguage(language)
    }

    public func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        try await prepare()
        guard let container else {
            throw .transformFailed(kind: kind, description: "the local model did not load")
        }

        do {
            // A fresh session per utterance: dictation is one-shot, and carrying
            // context between unrelated sentences would let one bleed into the next.
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
