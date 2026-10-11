// Owns model release across active passes.

extension MLXCandidateScorer {
    /// Empties the weights once every pass using them has ended, and hands the freed GPU buffers back to the system.
    public func release() async {
        container = nil
        await inFlightLoad.cancel()
        forgetReadings()
        await passesEnded()
        bufferCachePasses.begin()
        await weights.unload()
        bufferCachePasses.end()
    }

    /// Empties the prefix buckets kept across releases; for a release no query will undo, unlike an idle one.
    public nonisolated func forgetPrefixIndex() {
        prefixIndex.forget()
    }

    /// Drops everything read from the weights.
    func forgetReadings() {
        warm = nil
        prompt = nil
        vocabulary = nil
        kept = nil
        judgementCache.forgetEverything()
        confidenceMemory.forgetEverything()
    }

    /// Forgets every judged candidate, confidence and tokenised prompt line without releasing the model.
    public func forgetEverything() async {
        forgetGeneration &+= 1
        kept = nil
        prompt?.forgetEverything()
        judgementCache.forgetEverything()
        confidenceMemory.forgetEverything()
    }

    /// Marks a pass as using the model.
    func beginPass() {
        bufferCachePasses.begin()
        passesRunning += 1
    }

    /// Marks a pass as done, resuming a release that was waiting for the last one.
    func endPass() {
        passesRunning -= 1
        bufferCachePasses.end()
        guard passesRunning == 0 else { return }
        let waiting = waitingForPasses
        waitingForPasses = []
        waiting.forEach { $0.resume() }
    }

    /// Returns once no pass is using the model.
    func passesEnded() async {
        guard passesRunning > 0 else { return }
        await withCheckedContinuation { waitingForPasses.append($0) }
    }
}
