import Foundation
import Testing
import os

@testable import UttrflowLocalModel

/// A scripted model: every token scores its id divided by ten, and the cut's mass is the sum of the tokens asked for.
private final class FakeBackend: CandidateScoringBackend {
    struct Call: Equatable {
        let values: [Int]
        let massOffset: Int?
        let massTokens: [Int]
    }

    private let calls = OSAllocatedUnfairLock<[Call]>(initialState: [])
    private let input: CandidateScoringInput
    private let failingCall: Int?
    private let onScore: @Sendable (Int) -> Void

    init(
        input: CandidateScoringInput, failingCall: Int? = nil,
        onScore: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.input = input
        self.failingCall = failingCall
        self.onScore = onScore
    }

    var recorded: [Call] { calls.withLock { $0 } }

    func prepare(
        candidate: String, following context: String, vocabulary: TokenHealing.Vocabulary
    ) async -> CandidateScoringInput {
        input
    }

    func score(_ values: [Int], massOffset: Int?, massTokens: [Int]) async throws -> CandidateScoringChunk {
        let index = calls.withLock {
            $0.append(Call(values: values, massOffset: massOffset, massTokens: massTokens))
            return $0.count - 1
        }
        onScore(index)
        if index == failingCall { throw CancellationError() }
        return CandidateScoringChunk(
            tokenScores: values.map { Float($0) / 10 },
            prefixMass: massOffset == nil ? nil : Float(massTokens.reduce(0, +)))
    }
}

private struct PassRecorder: Sendable {
    let log = OSAllocatedUnfairLock<[String]>(initialState: [])

    var passes: BufferCachePasses {
        BufferCachePasses(
            control: BufferCacheControl(
                hold: { log.withLock { $0.append("hold") } },
                clear: { log.withLock { $0.append("clear") } }))
    }
}

@Suite("Chunked candidate judging")
struct ChunkedCandidateJudgeTests {
    /// Token 1 writes "a", 2 writes "ab", 3 writes "abc", 4 writes "b"; ids from 5 up write one other byte each.
    private let vocabulary = TokenHealing.Vocabulary(
        bytes: [[0x20], [0x61], [0x61, 0x62], [0x61, 0x62, 0x63], [0x62]]
            + (0..<400).map { [UInt8(0x80 + $0 % 40)] },
        ending: [])

    private func input(count: Int, prefixStart: Int? = nil) -> CandidateScoringInput {
        let tokens = (0..<count).map { $0 + 5 }
        return CandidateScoringInput(
            tokens: tokens, typedTokens: [5, 6], texts: tokens.map { "t\($0)" }, prefixStart: prefixStart)
    }

    private func judge(
        _ backend: FakeBackend, passes: BufferCachePasses
    ) async throws -> ChunkedCandidateJudgement {
        try await ChunkedCandidateJudge.judge(
            "abc", following: "a", vocabulary: vocabulary, using: backend, holding: passes)
    }

    @Test("No tokens give an empty line that keeps the typed tokens, and the model is never run.")
    func emptyCandidate() async throws {
        let recorder = PassRecorder()
        let backend = FakeBackend(
            input: CandidateScoringInput(
                tokens: [], typedTokens: [7], texts: [], prefixStart: nil))
        let result = try await judge(backend, passes: recorder.passes)
        #expect(result.line.isEmpty)
        #expect(result.typedTokens == [7])
        #expect(backend.recorded.isEmpty)
        #expect(recorder.log.withLock { $0 } == ["hold", "clear"])
    }

    @Test("A short candidate is scored in one run and each token keeps its own score and text.")
    func oneChunk() async throws {
        let backend = FakeBackend(input: input(count: 4))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded == [.init(values: [5, 6, 7, 8], massOffset: nil, massTokens: [])])
        #expect(result.line.tokens == [5, 6, 7, 8])
        #expect(result.line.tokenLogProbabilities == [0.5, 0.6, 0.7, 0.8])
        #expect(result.line.texts == ["t5", "t6", "t7", "t8"])
        #expect(result.line.prefixLogMasses == [nil, nil, nil, nil])
        #expect(result.line.prefixMassIndex == nil)
        #expect(result.typedTokens == [5, 6])
    }

    @Test("A long candidate is scored in order, one token-limit run at a time, and joined back whole.")
    func manyChunksKeepOrder() async throws {
        let count = CancellableModelChunks.tokenLimit * 2 + 3
        let backend = FakeBackend(input: input(count: count))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded.map(\.values.count) == [128, 128, 3])
        #expect(backend.recorded.flatMap(\.values) == result.line.tokens)
        #expect(result.line.tokenLogProbabilities == result.line.tokens.map { Float($0) / 10 })
        #expect(result.line.prefixLogMasses.count == count)
    }

    @Test("The cut's mass is asked for once, in the run holding the cut, over its continuing tokens.")
    func prefixMassInTheRunHoldingTheCut() async throws {
        // Token 1 writes "a"; 2 and 3 continue it and 1 is the cut token itself.
        var tokens = Array(repeating: 9, count: 130)
        tokens[129] = 1
        let backend = FakeBackend(
            input: CandidateScoringInput(
                tokens: tokens, typedTokens: [], texts: tokens.map(String.init), prefixStart: 129))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded.map(\.massOffset) == [nil, 1])
        #expect(backend.recorded[1].massTokens == [2, 3])
        #expect(result.line.prefixMassIndex == 129)
        #expect(result.line.prefixLogMasses[129] == 5)
        #expect(result.line.prefixLogMasses.compactMap { $0 }.count == 1)
    }

    @Test("A cut with no continuing token asks for no mass and records none.")
    func cutWithNothingContinuing() async throws {
        // Token 4 writes "b", which nothing but itself starts with.
        let backend = FakeBackend(
            input: CandidateScoringInput(
                tokens: [9, 4, 9], typedTokens: [], texts: ["x", "y", "z"], prefixStart: 1))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded == [.init(values: [9, 4, 9], massOffset: nil, massTokens: [])])
        #expect(result.line.prefixLogMasses == [nil, nil, nil])
        #expect(result.line.prefixMassIndex == 1)
    }

    @Test("A cut that falls outside every token is never asked about.")
    func cutBeyondTheLine() async throws {
        let backend = FakeBackend(input: input(count: 3, prefixStart: 3))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded.map(\.massOffset) == [nil])
        #expect(result.line.prefixLogMasses == [nil, nil, nil])
    }

    @Test("A failing run ends the judgement with its error and still releases the cache.")
    func errorStopsAndReleases() async {
        let recorder = PassRecorder()
        let backend = FakeBackend(input: input(count: 300), failingCall: 1)
        await #expect(throws: CancellationError.self) {
            try await judge(backend, passes: recorder.passes)
        }
        #expect(backend.recorded.count == 2)
        #expect(recorder.log.withLock { $0 } == ["hold", "clear"])
    }

    @Test("A judgement cancelled between runs scores no further run.")
    func cancellationBetweenRuns() async {
        let recorder = PassRecorder()
        let backend = FakeBackend(input: input(count: 300)) { index in
            if index == 0 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let passes = recorder.passes
        _ = await Task { try? await judge(backend, passes: passes) }.value
        #expect(backend.recorded.count == 1)
        #expect(recorder.log.withLock { $0 } == ["hold", "clear"])
    }

    @Test("A judgement turns into the per-token scores past the typed opening.")
    func judgementReadsAsTokens() async throws {
        let backend = FakeBackend(input: input(count: 4))
        let result = try await judge(backend, passes: PassRecorder().passes)
        let tokens = result.judged(using: vocabulary)
        #expect(tokens.map(\.text) == ["t7", "t8"])
    }
}
