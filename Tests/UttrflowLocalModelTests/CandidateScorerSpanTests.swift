import Testing

@testable import UttrflowLocalModel

/// Where the model's judgement of a candidate starts, decided without loading a model.
@Suite("Candidate scoring span")
struct CandidateScorerSpanTests {
    @Test("The typed opening is taken from the candidate itself, so the two tokenise the same way.")
    func typedPartComesFromTheCandidate() {
        #expect(CompletionText.typedPart(of: "ls -l", following: "ls") == "ls")
        #expect(CompletionText.typedPart(of: "ls -l", following: "ls ") == "ls ")
        #expect(CompletionText.typedPart(of: "git checkout main", following: "git c") == "git c")
    }

    @Test("A candidate matched without regard to case keeps its own spelling of the typed part.")
    func typedPartKeepsTheCandidatesCase() {
        #expect(CompletionText.typedPart(of: "Git status", following: "git s") == "Git s")
    }

    @Test("A typed opening folding to another length, as SS against ß, is still found.")
    func typedPartUsesTheSharedFold() {
        #expect(CompletionText.typedPart(of: "Straße is", following: "STRASSE") == "Straße")
    }

    @Test("A candidate that does not carry what was typed is judged whole, with nothing taken as typed.")
    func fuzzyCandidateHasNoTypedPart() {
        #expect(CompletionText.typedPart(of: "git status", following: "gti s").isEmpty)
        #expect(CompletionText.typedPart(of: "ls", following: "ls -l").isEmpty)
    }

    @Test("Nothing typed means nothing of the candidate is skipped.")
    func emptyContextHasNoTypedPart() {
        #expect(CompletionText.typedPart(of: "ls -l", following: "").isEmpty)
    }

    @Test("Scoring starts after the tokens the typed opening shares with the whole line.")
    func startsAfterTheSharedTokens() {
        #expect(ScoredSpan(whole: [2, 10, 11, 12], typed: [2, 10], bytes: [])?.start == 2)
    }

    @Test("A join that retokenises is scored from where the streams diverge, not from where the text ends.")
    func retokenisedJoinStartsAtTheDivergence() {
        #expect(ScoredSpan(whole: [2, 10, 30, 12], typed: [2, 10, 11], bytes: [])?.start == 2)
    }

    @Test("The first token is never scored, since nothing predicts it.")
    func firstTokenIsNeverScored() {
        #expect(ScoredSpan(whole: [10, 11], typed: [], bytes: [])?.start == 1)
        #expect(ScoredSpan(whole: [10, 11], typed: [99], bytes: [])?.start == 1)
    }

    @Test("A candidate with nothing past what was typed has nothing to be judged on.")
    func nothingLeftToScore() {
        #expect(ScoredSpan(whole: [2, 10], typed: [2, 10], bytes: [])?.start == nil)
        #expect(ScoredSpan(whole: [2, 10], typed: [2, 10, 11], bytes: [])?.start == nil)
        #expect(ScoredSpan(whole: [10], typed: [], bytes: [])?.start == nil)
        #expect(ScoredSpan(whole: [], typed: [], bytes: [])?.start == nil)
    }
}

/// The per-candidate judgements `MLXCandidateScorer` answers from a cache, so a keystroke that re-types the same line skips the forward pass.
@Suite("MLX candidate scorer judgement cache")
struct MLXCandidateScorerJudgementCacheTests {
    @Test("Scoring the same candidate after five successive prefixes computes once and is read four times")
    func sameCandidateFivePrefixesRunsOnce() async {
        let scorer = MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16, bufferCache: Self.noOpCache)
        _ = await scorer.judgedTokens(of: "please send the report", following: "pl")
        #expect(await scorer.judgementCacheMisses == 1)
        _ = await scorer.judgedTokens(of: "please send the report", following: "ple")
        _ = await scorer.judgedTokens(of: "please send the report", following: "plea")
        _ = await scorer.judgedTokens(of: "please send the report", following: "pleas")
        _ = await scorer.judgedTokens(of: "please send the report", following: "please")
        #expect(await scorer.judgementCacheMisses == 1)
        #expect(await scorer.judgementCacheHits == 4)
    }

    @Test("Different candidates each compute once")
    func differentCandidatesEachCompute() async {
        let scorer = MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16, bufferCache: Self.noOpCache)
        _ = await scorer.judgedTokens(of: "please send the report", following: "p")
        _ = await scorer.judgedTokens(of: "please send the memo", following: "p")
        _ = await scorer.judgedTokens(of: "please send the memo", following: "pl")
        #expect(await scorer.judgementCacheMisses == 2)
        #expect(await scorer.judgementCacheHits == 1)
    }

    @Test("A release empties the cache, so a re-loaded scorer starts cold")
    func releaseEmptiesTheCache() async {
        let scorer = MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16, bufferCache: Self.noOpCache)
        _ = await scorer.judgedTokens(of: "please send the report", following: "p")
        #expect(await scorer.judgementCacheMisses == 1)
        await scorer.release()
        _ = await scorer.judgedTokens(of: "please send the report", following: "p")
        #expect(await scorer.judgementCacheMisses == 2)
        #expect(await scorer.judgementCacheHits == 0)
    }

    @Test("Forgetting clears judged candidates and generated confidence without releasing the model")
    func forgetEmptiesBothCaches() async {
        var confidence = ConfidenceMemory()
        confidence.remember(["please send the report": -0.25])
        let scorer = MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16, bufferCache: Self.noOpCache,
            initialConfidenceMemory: confidence)

        #expect(await scorer.confidence(ofGenerated: "please send the report") == -0.25)
        _ = await scorer.judgedTokens(of: "please send the report", following: "p")
        _ = await scorer.judgedTokens(of: "please send the report", following: "pl")
        #expect(await scorer.judgementCacheHits == 1)
        #expect(!(await scorer.isReady))

        await scorer.forgetEverything()

        #expect(await scorer.confidence(ofGenerated: "please send the report") == nil)
        _ = await scorer.judgedTokens(of: "please send the report", following: "ple")
        #expect(await scorer.judgementCacheMisses == 2)
        #expect(await scorer.judgementCacheHits == 1)
        #expect(!(await scorer.isReady))
    }

    @Test("Forgetting suggestions empties cached candidate text")
    func forgettingSuggestionsEmptiesTheCache() async {
        let scorer = MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16, bufferCache: Self.noOpCache)
        _ = await scorer.judgedTokens(of: "please send the report", following: "p")
        #expect(await scorer.judgementCacheMisses == 1)
        #expect(await scorer.judgementCacheCount == 1)

        await scorer.forgetEverything()
        #expect(await scorer.judgementCacheCount == 0)
        _ = await scorer.judgedTokens(of: "please send the report", following: "p")

        #expect(await scorer.judgementCacheMisses == 2)
        #expect(await scorer.judgementCacheHits == 0)
    }

    @Test("A cancelled scoring attempt leaves nothing cached, so the next attempt runs afresh")
    func cancelledAttemptIsNotCached() async {
        let scorer = MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16, bufferCache: Self.noOpCache)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await scorer.judgedTokens(of: "please send the report", following: "p")
        }
        #expect(await cancelled.value.isEmpty)
        #expect(await scorer.judgementCacheMisses == 1)
        _ = await scorer.judgedTokens(of: "please send the report", following: "p")
        #expect(await scorer.judgementCacheMisses == 2)
        #expect(await scorer.judgementCacheHits == 0)
    }

    /// A buffer cache that does nothing, since the test does not load a model.
    private static let noOpCache = BufferCacheControl(hold: {}, clear: {})
}

@Suite("Prefix-mass readback")
struct PrefixMassReadbackTests {
    @Test("A judged line reads token scores and its requested prefix mass in one batch")
    func batchesCandidateReadback() {
        var batches = 0
        let result = JudgementReadback.read(
            tokenScores: [Float(1), 2, 3], prefixMasses: [nil, 4, nil]
        ) { values in
            batches += 1
            return values
        }

        #expect(batches == 1)
        #expect(result.tokenScores == [Float(1), 2, 3])
        #expect(result.prefixMasses == [nil, 4, nil])
    }
}
