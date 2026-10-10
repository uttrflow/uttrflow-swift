import Foundation
import MLX
import MLXLMCommon
import MLXNN
import UttrflowCore

struct ChunkedCandidateJudgement: Sendable {
    let line: JudgedLine
    let typedTokens: [Int]

    func judged(using vocabulary: TokenHealing.Vocabulary) -> [JudgedToken] {
        JudgedLine.judged(from: line, typedTokens: typedTokens, vocabulary: vocabulary)
    }
}

private struct CandidateScoringInput: Sendable {
    let tokens: [Int]
    let typedTokens: [Int]
    let texts: [String]
    let prefixStart: Int?
}

private struct CandidateScoringChunk: Sendable {
    let tokenScores: [Float]
    let prefixMasses: [Float?]
}

enum ChunkedCandidateJudge {
    static func judge(
        _ candidate: String, following context: String,
        vocabulary: TokenHealing.Vocabulary, in container: ModelContainer
    ) async throws -> ChunkedCandidateJudgement {
        let input = await container.perform { modelContext in
            let tokens = MLXCandidateScorer.leadIn + candidate
            let whole = modelContext.tokenizer.encode(text: tokens)
            let typed = modelContext.tokenizer.encode(
                text: MLXCandidateScorer.leadIn
                    + CompletionText.typedPart(of: candidate, following: context))
            return CandidateScoringInput(
                tokens: whole,
                typedTokens: typed,
                texts: whole.map { modelContext.tokenizer.decode(tokenIds: [$0]) },
                prefixStart: MLXCandidateScorer.requestedStart(
                    whole, candidate: candidate, context: context,
                    vocabulary: vocabulary, tokenizer: modelContext.tokenizer))
        }
        guard !input.tokens.isEmpty else {
            return ChunkedCandidateJudgement(
                line: JudgedLine(
                    tokens: [], tokenLogProbabilities: [], prefixLogMasses: [], texts: []),
                typedTokens: input.typedTokens)
        }

        let cache = ModelCacheTransfer()
        let starts = stride(
            from: 0, to: input.tokens.count, by: CancellableModelChunks.tokenLimit
        ).map { $0 }
        let chunks = try await CancellableModelChunks.run(starts, chunkSize: 1) { unit in
            let start = unit.first ?? 0
            let end = min(start + CancellableModelChunks.tokenLimit, input.tokens.count)
            let values = Array(input.tokens[start..<end])
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
                    let token = values[offset]
                    scores.append(row[token])
                    let position = start + offset
                    guard position == input.prefixStart else { continue }
                    let bytes = ScoredSpan.written(by: token, in: vocabulary.bytes)
                    let continuing = ScoredSpan.continuing(bytes, in: vocabulary).filter { $0 != token }
                    masses[offset] = Self.logMass(of: continuing, in: row)
                }
                let readback = JudgementReadback.read(
                    tokenScores: scores, prefixMasses: masses
                ) { scalars in
                    concatenated(scalars.map { $0.expandedDimensions(axis: 0) }).asArray(Float.self)
                }
                eval(layers)
                cache.layers = layers
                return CandidateScoringChunk(
                    tokenScores: readback.tokenScores, prefixMasses: readback.prefixMasses)
            }
        }
        let line = JudgedLine(
            tokens: input.tokens,
            tokenLogProbabilities: chunks.flatMap(\.tokenScores),
            prefixLogMasses: chunks.flatMap(\.prefixMasses),
            prefixMassIndex: input.prefixStart,
            texts: input.texts)
        return ChunkedCandidateJudgement(line: line, typedTokens: input.typedTokens)
    }

    private static func logMass(of tokens: [Int], in row: MLXArray) -> MLXArray? {
        guard !tokens.isEmpty else { return nil }
        return row[MLXArray(tokens.map(Int32.init))].logSumExp()
    }
}
