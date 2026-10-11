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
    private let asked = OSAllocatedUnfairLock<[String]>(initialState: [])
    private let read: CandidateTokens
    private let failingCall: Int?
    private let onScore: @Sendable (Int) -> Void

    init(
        read: CandidateTokens, failingCall: Int? = nil,
        onScore: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.read = read
        self.failingCall = failingCall
        self.onScore = onScore
    }

    var recorded: [Call] { calls.withLock { $0 } }

    /// The whole line's text, then the typed opening's, as the judge asked for them.
    var askedTexts: [String] { asked.withLock { $0 } }

    func tokenise(whole: String, typed: String) async -> CandidateTokens {
        asked.withLock { $0 += [whole, typed] }
        return read
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

    /// A line of `count` tokens, ids from 5, whose typed opening is its first `typed` tokens.
    private func line(count: Int, typed: Int = 2) -> CandidateTokens {
        let tokens = (0..<count).map { $0 + 5 }
        return CandidateTokens(
            whole: tokens, typed: Array(tokens.prefix(typed)), texts: tokens.map { "t\($0)" })
    }

    private func judge(
        _ backend: FakeBackend, passes: BufferCachePasses
    ) async throws -> ChunkedCandidateJudgement {
        try await ChunkedCandidateJudge.judge(
            "abc", following: "a", vocabulary: vocabulary, using: backend, holding: passes)
    }

    @Test("The model is asked for the lead-in and the whole candidate, then the lead-in and what was typed.")
    func asksForBothTexts() async throws {
        let backend = FakeBackend(read: line(count: 4))
        _ = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.askedTexts == [MLXCandidateScorer.leadIn + "abc", MLXCandidateScorer.leadIn + "a"])
    }

    @Test("No tokens give an empty line that keeps the typed tokens, and the model is never run.")
    func emptyCandidate() async throws {
        let recorder = PassRecorder()
        let backend = FakeBackend(read: CandidateTokens(whole: [], typed: [7], texts: []))
        let result = try await judge(backend, passes: recorder.passes)
        #expect(result.line.isEmpty)
        #expect(result.typedTokens == [7])
        #expect(backend.recorded.isEmpty)
        #expect(recorder.log.withLock { $0 } == ["hold", "clear"])
    }

    @Test("A short candidate is scored in one run and each token keeps its own score and text.")
    func oneChunk() async throws {
        let backend = FakeBackend(read: line(count: 4, typed: 4))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded == [.init(values: [5, 6, 7, 8], massOffset: nil, massTokens: [])])
        #expect(result.line.tokens == [5, 6, 7, 8])
        #expect(result.line.tokenLogProbabilities == [0.5, 0.6, 0.7, 0.8])
        #expect(result.line.texts == ["t5", "t6", "t7", "t8"])
        #expect(result.line.prefixLogMasses == [nil, nil, nil, nil])
        #expect(result.line.prefixMassIndex == nil)
        #expect(result.typedTokens == [5, 6, 7, 8])
    }

    @Test("A long candidate is scored in order, one token-limit run at a time, and joined back whole.")
    func manyChunksKeepOrder() async throws {
        let count = CancellableModelChunks.tokenLimit * 2 + 3
        let backend = FakeBackend(read: line(count: count))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded.map(\.values.count) == [128, 128, 3])
        #expect(backend.recorded.flatMap(\.values) == result.line.tokens)
        #expect(result.line.tokenLogProbabilities == result.line.tokens.map { Float($0) / 10 })
        #expect(result.line.prefixLogMasses.count == count)
        #expect(result.line.prefixMassIndex == 2)
    }

    @Test("The cut's mass is asked for once, in the run holding the cut, over its continuing tokens.")
    func prefixMassInTheRunHoldingTheCut() async throws {
        // Token 1 writes "a"; 2 and 3 continue it and 1 is the cut token itself.
        var tokens = Array(repeating: 9, count: 130)
        tokens[129] = 1
        let typed = Array(tokens.prefix(129))
        let backend = FakeBackend(
            read: CandidateTokens(whole: tokens, typed: typed, texts: tokens.map(String.init)))
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
            read: CandidateTokens(whole: [9, 4, 9], typed: [9], texts: ["x", "y", "z"]))
        let result = try await judge(backend, passes: PassRecorder().passes)
        #expect(backend.recorded == [.init(values: [9, 4, 9], massOffset: nil, massTokens: [])])
        #expect(result.line.prefixLogMasses == [nil, nil, nil])
        #expect(result.line.prefixMassIndex == 1)
    }

    @Test("A failing run ends the judgement with its error and still releases the cache.")
    func errorStopsAndReleases() async {
        let recorder = PassRecorder()
        let backend = FakeBackend(read: line(count: 300), failingCall: 1)
        await #expect(throws: CancellationError.self) {
            try await judge(backend, passes: recorder.passes)
        }
        #expect(backend.recorded.count == 2)
        #expect(recorder.log.withLock { $0 } == ["hold", "clear"])
    }

    @Test("A judgement cancelled between runs scores no further run.")
    func cancellationBetweenRuns() async {
        let recorder = PassRecorder()
        let backend = FakeBackend(read: line(count: 300)) { index in
            if index == 0 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let passes = recorder.passes
        _ = await Task { try? await judge(backend, passes: passes) }.value
        #expect(backend.recorded.count == 1)
        #expect(recorder.log.withLock { $0 } == ["hold", "clear"])
    }

    @Test("A judgement turns into the per-token scores past the typed opening.")
    func judgementReadsAsTokens() async throws {
        let backend = FakeBackend(read: line(count: 4))
        let result = try await judge(backend, passes: PassRecorder().passes)
        let tokens = result.judged(using: vocabulary)
        #expect(tokens.map(\.text) == ["t7", "t8"])
    }
}
