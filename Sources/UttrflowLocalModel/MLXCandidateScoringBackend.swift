import Foundation
import MLX
import MLXLMCommon
import MLXNN

/// The MLX end of candidate judging: the tokenizer and the forward pass, kept thin because MLX cannot run under `swift test`.
struct MLXCandidateScoringBackend: CandidateScoringBackend {
    let container: ModelContainer
    private let bufferCachePasses: BufferCachePasses
    private let cache = ModelCacheTransfer()

    init(container: ModelContainer, holding bufferCachePasses: BufferCachePasses) {
        self.container = container
        self.bufferCachePasses = bufferCachePasses
    }

    func tokenise(whole: String, typed: String) async -> CandidateTokens {
        bufferCachePasses.begin()
        defer { bufferCachePasses.end() }
        return await container.perform { context in
            let ids = context.tokenizer.encode(text: whole)
            return CandidateTokens(
                whole: ids, typed: context.tokenizer.encode(text: typed),
                texts: ids.map { context.tokenizer.decode(tokenIds: [$0]) })
        }
    }

    func score(
        _ values: [Int], massOffset: Int?, massTokens: [Int]
    ) async throws -> CandidateScoringChunk {
        bufferCachePasses.begin()
        defer { bufferCachePasses.end() }
        let cache = cache
        return try await container.perform { modelContext in
            try Task.checkCancellation()
            let layers = cache.layers ?? modelContext.model.newCache(parameters: nil)
            let tokens = MLXArray(values.map(Int32.init)).expandedDimensions(axis: 0)
            let output = withPreparedCache(layers, lengths: [values.count]) {
                modelContext.model(LMInput.Text(tokens: tokens), cache: layers, state: nil)
            }
            let probabilities = logSoftmax(output.logits.asType(.float32), axis: -1)[0]
            var scores: [MLXArray] = []
            var masses = [MLXArray?](repeating: nil, count: values.count)
            scores.reserveCapacity(values.count)
            for offset in values.indices {
                let row = probabilities[offset]
                scores.append(row[values[offset]])
                if offset == massOffset {
                    masses[offset] = row[MLXArray(massTokens.map(Int32.init))].logSumExp()
                }
            }
            let readback = JudgementReadback.read(tokenScores: scores, prefixMasses: masses) { scalars in
                concatenated(scalars.map { $0.expandedDimensions(axis: 0) }).asArray(Float.self)
            }
            eval(layers)
            cache.layers = layers
            return CandidateScoringChunk(
                tokenScores: readback.tokenScores,
                prefixMass: massOffset.flatMap { readback.prefixMasses[$0] })
        }
    }
}

extension ChunkedCandidateJudge {
    /// Judges through the loaded model.
    static func judge(
        _ candidate: String, following context: String,
        vocabulary: TokenHealing.Vocabulary, in container: ModelContainer,
        holding bufferCachePasses: BufferCachePasses
    ) async throws -> ChunkedCandidateJudgement {
        try await judge(
            candidate, following: context, vocabulary: vocabulary,
            using: MLXCandidateScoringBackend(container: container, holding: bufferCachePasses),
            holding: bufferCachePasses)
    }
}
