public import UttrflowPredict

// The MLX macros expand to code naming these types, so the imports cannot be private.
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import Tokenizers

/// Scores how likely a candidate is where it stands, in one forward pass. See `Docs/predict.md`.
public actor MLXCandidateScorer: CandidateScoring {
    private let model: LocalModel
    private var container: ModelContainer?

    public init(model: LocalModel) {
        self.model = model
    }

    /// Downloads and loads the weights, which a caller pays for deliberately rather than in a keystroke.
    public func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard container == nil else { return }
        container = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: model.identifier),
            progressHandler: { onProgress($0.fractionCompleted) }
        )
    }

    public var isReady: Bool { container != nil }

    public func logLikelihood(of candidate: String, following context: String) async -> Double? {
        guard let container, !Task.isCancelled else { return nil }
        return await container.perform { loaded in
            Self.score(candidate, following: context, with: loaded)
        }
    }

    /// The mean log-probability the model gives the candidate's own tokens, nothing generated.
    private static func score(
        _ candidate: String, following context: String, with loaded: ModelContext
    ) -> Double? {
        let prefix = loaded.tokenizer.encode(text: context)
        let whole = loaded.tokenizer.encode(text: context + candidate)
        let start = max(prefix.count, 1)
        guard whole.count > start else { return nil }

        let tokens = MLXArray(whole.map(Int32.init)).expandedDimensions(axis: 0)
        let output = loaded.model(LMInput.Text(tokens: tokens), cache: nil, state: nil)
        let probabilities = logSoftmax(output.logits, axis: -1)[0]
        let targets = MLXArray(whole[start...].map(Int32.init)).expandedDimensions(axis: 1)
        let taken = takeAlong(probabilities[(start - 1)..<(whole.count - 1)], targets, axis: 1)
        let mean = taken.mean()
        eval(mean)
        return mean.item(Double.self)
    }
}
