import Foundation
import Testing

@testable import UttrflowLocalModel

/// The cache that holds a candidate's per-token log-softmax rows, so a keystroke after the first is read from memory.
@Suite("MLX candidate scorer judgement cache")
struct JudgementCacheTests {
    @Test("A candidate remembered once is read back unchanged.")
    func roundTripsTheLine() {
        var cache = JudgementCache()
        let line = JudgedLine(
            tokens: [1, 2, 3], tokenLogProbabilities: [0.1, 0.2, 0.3],
            prefixLogMasses: [nil, nil, nil], texts: ["a", "b", "c"])
        cache.remember(line, for: "please")
        #expect(cache.recall(candidate: "please") == line)
    }

    @Test("A candidate never remembered reads as nothing.")
    func anUnseenCandidateMisses() {
        var cache = JudgementCache()
        #expect(cache.recall(candidate: "never scored") == nil)
    }

    @Test("Re-remembering a candidate does not grow the cache and refreshes its recency.")
    func reRememberingRefreshesRecency() {
        var cache = JudgementCache()
        let first = JudgedLine(
            tokens: [1], tokenLogProbabilities: [0.1], prefixLogMasses: [nil], texts: ["a"])
        let second = JudgedLine(
            tokens: [2], tokenLogProbabilities: [0.2], prefixLogMasses: [nil], texts: ["b"])
        cache.remember(first, for: "alpha")
        cache.remember(second, for: "alpha")
        #expect(cache.count == 1)
        #expect(cache.recall(candidate: "alpha") == second)
    }

    @Test("Recalling a candidate keeps it alive through a full capacity of new candidates.")
    func recallingRefreshesRecency() {
        var cache = JudgementCache()
        let line = JudgedLine(tokens: [1], tokenLogProbabilities: [0.1], prefixLogMasses: [nil], texts: ["a"])
        cache.remember(line, for: "candidate-A")

        for index in 0..<JudgementCache.capacity {
            let recalled = cache.recall(candidate: "candidate-A")
            #expect(recalled == line)
            let other = JudgedLine(
                tokens: [index], tokenLogProbabilities: [Float(index)], prefixLogMasses: [nil],
                texts: ["\(index)"])
            cache.remember(other, for: "candidate-\(index)")
        }

        #expect(cache.count == JudgementCache.capacity)
        #expect(cache.recall(candidate: "candidate-A") == line)
        #expect(cache.recall(candidate: "candidate-0") == nil)
    }

    @Test("Capacity drops the oldest candidate, never the most recent.")
    func capacityEvictsTheOldest() {
        var cache = JudgementCache()
        for index in 0..<(JudgementCache.capacity + 3) {
            let line = JudgedLine(
                tokens: [index], tokenLogProbabilities: [Float(index)], prefixLogMasses: [nil],
                texts: ["\(index)"])
            cache.remember(line, for: "candidate-\(index)")
        }
        #expect(cache.count == JudgementCache.capacity)
        #expect(cache.recall(candidate: "candidate-0") == nil)
        #expect(cache.recall(candidate: "candidate-1") == nil)
        #expect(cache.recall(candidate: "candidate-3") != nil)
    }

    @Test("Forget everything empties the cache, so the next recall misses.")
    func forgetEverythingClears() {
        var cache = JudgementCache()
        cache.remember(
            JudgedLine(tokens: [1], tokenLogProbabilities: [0.1], prefixLogMasses: [nil], texts: ["a"]),
            for: "alpha")
        cache.forgetEverything()
        #expect(cache.count == 0)
        #expect(cache.recall(candidate: "alpha") == nil)
    }
}

/// A vocabulary the `bytes` table can look bytes up in, used by `JudgedLine.judged`. Token 0 is BOS, 1 is "p", 2 is "pl", 3 is "ple", 4 is "lease".
private let scorerBytes: [[UInt8]] = [
    "<bos>", "p", "pl", "ple", "lease", " ", "send", " the", " report",
].map { Array($0.utf8) }
private let scorerVocabulary = TokenHealing.Vocabulary(
    bytes: [
        "<bos>", "p", "pl", "ple", "lease", " ", "send", " the", " report",
    ].map { Array($0.utf8) }, ending: [])

@Suite("A cached line answers each new typed prefix from the same rows")
struct JudgedLineTests {
    @Test("A typed prefix that ends on a token boundary is read straight from the cache.")
    func typedOnBoundaryReturnsCachedTokens() {
        let tokens = [0, 2, 3, 4, 5, 6, 7]
        let tokenLogProbabilities = Array(repeating: Float(-10), count: tokens.count)
        let texts = tokens.map { _ in "x" }
        let line = JudgedLine(
            tokens: tokens, tokenLogProbabilities: tokenLogProbabilities,
            prefixLogMasses: Array(repeating: nil, count: tokens.count), texts: texts)
        let typed = [0, 2]
        let judged = JudgedLine.judged(
            from: line, typedTokens: typed,
            vocabulary: TokenHealing.Vocabulary(bytes: scorerBytes, ending: []))
        #expect(judged.count == tokens.count - 2)
        #expect(judged.map(\.logProbability) == [-10, -10, -10, -10, -10])
    }

    @Test("A typed prefix that ends mid-token returns the slice from the cached rows.")
    func typedMidTokenReturnsTheSlice() {
        let tokens = [0, 3, 4, 5, 6, 7]
        let tokenLogProbabilities = Array(repeating: Float(-10), count: tokens.count)
        let texts = tokens.map { _ in "x" }
        let line = JudgedLine(
            tokens: tokens, tokenLogProbabilities: tokenLogProbabilities,
            prefixLogMasses: Array(repeating: nil, count: tokens.count), texts: texts)
        let typed = [0, 1]
        let judged = JudgedLine.judged(
            from: line, typedTokens: typed,
            vocabulary: TokenHealing.Vocabulary(bytes: scorerBytes, ending: []))
        #expect(judged.count == tokens.count - 1)
        #expect(judged.map(\.logProbability) == [-10, -10, -10, -10, -10])
    }

    @Test("A cached mid-token judgement conditions on indexed rivals without changing its score")
    func cachedCutUsesPrefixIndexedRivals() throws {
        let tokens = [0, 3, 4]
        let vocabularyBytes =
            ["<bos>", "p", "pl", "please", "lease", "x"]
            .map { Array($0.utf8) } + (0..<2_000).map { Array("unrelated-\($0)".utf8) }
        let vocabulary = TokenHealing.Vocabulary(bytes: vocabularyBytes, ending: [])
        let line = JudgedLine(
            tokens: tokens,
            tokenLogProbabilities: [-8, -8, -8],
            prefixLogMasses: [nil, log(3) - 8, nil],
            prefixMassIndex: 1,
            texts: ["", "please", "lease"])
        var cache = JudgementCache()
        cache.remember(line, for: "please")

        let remembered = cache.recall(candidate: "please")
        let recalled = try #require(remembered)
        #expect(recalled == line)
        #expect(ScoredSpan.continuing(Array("pl".utf8), in: vocabulary) == [2, 3])
        vocabulary.resetExaminedEntries()
        let judged = JudgedLine.judged(from: recalled, typedTokens: [0, 1], vocabulary: vocabulary)
        #expect(vocabulary.examinedEntries == 3)
        #expect(judged.count == 2)
        #expect(abs(judged[0].logProbability + log(3)) < 1e-6)
        #expect(judged[1].logProbability == -8)

        let smallVocabulary = TokenHealing.Vocabulary(bytes: Array(vocabularyBytes.prefix(6)), ending: [])
        smallVocabulary.resetExaminedEntries()
        _ = JudgedLine.judged(from: recalled, typedTokens: [0, 1], vocabulary: smallVocabulary)
        #expect(smallVocabulary.examinedEntries == 3)
    }

    @Test("A zero-probability rival mass leaves the first token's score unconditioned")
    func cachedCutWithNoRivalMassKeepsItsScore() {
        let vocabulary = TokenHealing.Vocabulary(
            bytes: ["<bos>", "p", "pl", "please", "lease", "x"].map { Array($0.utf8) },
            ending: [])
        let line = JudgedLine(
            tokens: [0, 3, 4], tokenLogProbabilities: [-8, -0.25, -8],
            prefixLogMasses: [nil, -.infinity, nil], prefixMassIndex: 1,
            texts: ["", "please", "lease"])

        let judged = JudgedLine.judged(from: line, typedTokens: [0, 1], vocabulary: vocabulary)

        #expect(judged.map(\.logProbability) == [-8, -0.25])
    }

    @Test("A cached mass from a different typed-prefix position is ignored")
    func massFromDifferentPositionIsIgnored() {
        let line = JudgedLine(
            tokens: [0, 3, 4], tokenLogProbabilities: [-8, -8, -8],
            prefixLogMasses: [nil, nil, log(3) - 8], prefixMassIndex: 2,
            texts: ["", "please", "lease"])

        let judged = JudgedLine.judged(
            from: line, typedTokens: [0, 1], vocabulary: scorerVocabulary)

        #expect(judged.first?.logProbability == -8)
    }

    @Test("Keeping only the requested mass preserves the prior all-position score")
    func requestedMassPreservesPriorScore() {
        let tokens = [0, 3, 4]
        let tokenScores: [Float] = [-8, -8, -8]
        let priorMasses: [Float?] = [
            ScoredSpan.logSumExp([-2, -3]),
            ScoredSpan.logSumExp([-8, -8, -8]),
            ScoredSpan.logSumExp([-3, -4]),
        ]
        let allPositionLine = JudgedLine(
            tokens: tokens, tokenLogProbabilities: tokenScores,
            prefixLogMasses: priorMasses, prefixMassIndex: 1,
            texts: ["", "please", "lease"])
        let requestedOnlyLine = JudgedLine(
            tokens: tokens, tokenLogProbabilities: tokenScores,
            prefixLogMasses: [nil, priorMasses[1], nil], prefixMassIndex: 1,
            texts: ["", "please", "lease"])

        let allPositionScore = JudgedLine.judged(
            from: allPositionLine, typedTokens: [0, 1], vocabulary: scorerVocabulary)
        let requestedOnlyScore = JudgedLine.judged(
            from: requestedOnlyLine, typedTokens: [0, 1], vocabulary: scorerVocabulary)

        #expect(requestedOnlyScore == allPositionScore)
    }

    @Test("An empty cached line returns nothing rather than indexing out of bounds.")
    func emptyLineReturnsNothing() {
        let line = JudgedLine(tokens: [], tokenLogProbabilities: [], prefixLogMasses: [], texts: [])
        #expect(
            JudgedLine.judged(
                from: line, typedTokens: [], vocabulary: .init(bytes: [], ending: [])) == [])
    }
}
