import Foundation
import UttrflowCore

struct ChunkedCandidateJudgement: Sendable {
    let line: JudgedLine
    let typedTokens: [Int]

    func judged(using vocabulary: TokenHealing.Vocabulary) -> [JudgedToken] {
        JudgedLine.judged(from: line, typedTokens: typedTokens, vocabulary: vocabulary)
    }
}

/// A candidate as the model reads it: its tokens, the typed opening's tokens, each token's text and where the cut falls.
struct CandidateScoringInput: Sendable, Equatable {
    let tokens: [Int]
    let typedTokens: [Int]
    let texts: [String]
    let prefixStart: Int?
}

/// What one forward pass over a run of tokens gives back.
struct CandidateScoringChunk: Sendable, Equatable {
    let tokenScores: [Float]
    let prefixMass: Float?
}

/// The two model calls judging needs, so the logic around them runs without a model.
protocol CandidateScoringBackend: Sendable {
    /// Tokenises the candidate and the typed opening, and finds where the cut falls.
    func prepare(
        candidate: String, following context: String, vocabulary: TokenHealing.Vocabulary
    ) async -> CandidateScoringInput

    /// Scores `values` as the next run of the line, continuing every earlier run; reads the log mass of `massTokens` at `massOffset` when asked.
    func score(
        _ values: [Int], massOffset: Int?, massTokens: [Int]
    ) async throws -> CandidateScoringChunk
}

enum ChunkedCandidateJudge {
    static func judge(
        _ candidate: String, following context: String,
        vocabulary: TokenHealing.Vocabulary, using backend: some CandidateScoringBackend,
        holding bufferCachePasses: BufferCachePasses
    ) async throws -> ChunkedCandidateJudgement {
        // Taken here as well as by the caller, so the cap is held wherever the passes below run.
        bufferCachePasses.begin()
        defer { bufferCachePasses.end() }
        let input = await backend.prepare(
            candidate: candidate, following: context, vocabulary: vocabulary)
        guard !input.tokens.isEmpty else {
            return ChunkedCandidateJudgement(
                line: JudgedLine(
                    tokens: [], tokenLogProbabilities: [], prefixLogMasses: [], texts: []),
                typedTokens: input.typedTokens)
        }

        let starts = Array(stride(from: 0, to: input.tokens.count, by: CancellableModelChunks.tokenLimit))
        let chunks = try await CancellableModelChunks.run(starts, chunkSize: 1) { unit in
            let start = unit.first ?? 0
            let end = min(start + CancellableModelChunks.tokenLimit, input.tokens.count)
            let values = Array(input.tokens[start..<end])
            var massOffset: Int?
            var massTokens: [Int] = []
            if let cut = input.prefixStart, (start..<end).contains(cut) {
                let token = input.tokens[cut]
                let bytes = ScoredSpan.written(by: token, in: vocabulary.bytes)
                massTokens = ScoredSpan.continuing(bytes, in: vocabulary).filter { $0 != token }
                massOffset = massTokens.isEmpty ? nil : cut - start
            }
            return try await backend.score(values, massOffset: massOffset, massTokens: massTokens)
        }
        var masses = [Float?](repeating: nil, count: input.tokens.count)
        for (chunk, start) in zip(chunks, starts) {
            guard let mass = chunk.prefixMass, let cut = input.prefixStart, cut >= start else { continue }
            masses[cut] = mass
        }
        let line = JudgedLine(
            tokens: input.tokens,
            tokenLogProbabilities: chunks.flatMap(\.tokenScores),
            prefixLogMasses: masses,
            prefixMassIndex: input.prefixStart,
            texts: input.texts)
        return ChunkedCandidateJudgement(line: line, typedTokens: input.typedTokens)
    }
}
