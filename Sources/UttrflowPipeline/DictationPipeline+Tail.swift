import UttrflowCore

extension DictationPipeline {
    /// How long `stage` may take for the dictation that began at `mine`: its own limit, cut to what the tail has left, and nil when none is left.
    func tailLimit(_ stage: Duration, for mine: Int?) -> (limit: Duration, budgeted: Bool)? {
        guard let mine, let tail, tail.generation == mine else { return (stage, false) }
        let left = max(.zero, tailAllowance - tail.spent)
        guard left > .zero else { return nil }
        return left < stage ? (left, true) : (stage, false)
    }

    /// `tailLimit` for the dictionary and snippets, which only rearrange words in hand: never below `StageTimeout.rules`, so a spent or nearly spent tail does not skip them.
    func localTailLimit(_ stage: Duration, for mine: Int?) -> (limit: Duration, budgeted: Bool) {
        guard let allowed = tailLimit(stage, for: mine) else { return (StageTimeout.rules, true) }
        return allowed.limit < StageTimeout.rules ? (StageTimeout.rules, true) : allowed
    }

    /// Runs `work` against `allowed`, answering nil when the limit wins, and charges the time it took to the dictation's tail, whether it answered, timed out or threw.
    func withinTail<Success: Sendable>(
        _ allowed: (limit: Duration, budgeted: Bool), for mine: Int?,
        _ work: @escaping @Sendable () async throws -> Success
    ) async throws -> Success? {
        var outcome: Result<Success?, any Error> = .success(nil)
        let took = await clock.measure {
            do {
                outcome = .success(try await withStageTimeout(allowed.limit, clock: clock, work))
            } catch {
                outcome = .failure(error)
            }
        }
        if let mine, tail?.generation == mine { tail?.spent += took }
        return try outcome.get()
    }

    /// Notes in the dictation's account that a stage passed its words on unchanged; outside a dictation, nothing.
    func skipped(
        _ stage: CleaningRecord.SkippedStage.Stage, _ reason: CleaningRecord.SkippedStage.Reason,
        for mine: Int?
    ) {
        if let mine { keep(.skipped(stage, reason), for: mine) }
    }
}
