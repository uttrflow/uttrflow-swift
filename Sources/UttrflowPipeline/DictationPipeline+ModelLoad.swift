// Loading the speech model under its limit, and keeping a load that outlasts the limit.
import UttrflowCore

extension DictationPipeline {
    /// Loads the speech model so the first dictation is not the slow one. See `Docs/startup.md`.
    public func prepare() async {
        loadsUnderWay += 1
        defer { loadsUnderWay -= 1 }
        do {
            if let stillLoading = try await loadWithinLimit(speech) {
                let error = SpeechEngineError.modelLoadFailed(
                    description: "the load did not finish within \(speechLoadLimit)")
                adopt(stillLoading, replacing: loadFailed(error, as: .timedOut))
                return
            }
            isReady = true
            lastLoadFailure = nil
            // A retry that works clears the notice the failed attempt left behind.
            if case .failed = state, !isBusy { transition(to: .idle) }
        } catch {
            loadFailed(error, as: SpeechLoadFailureClass(error))
        }
    }

    /// Waits up to the load limit for `engine` to load, answering the load still running once the limit passes.
    func loadWithinLimit(_ engine: any SpeechEngine) async throws -> Task<Void, any Error>? {
        // The load runs in a task the limit never cancels, so a compile that outlasts the limit is kept.
        let load = Task { try await engine.prepare() }
        let finished = try await withStageTimeout(speechLoadLimit, clock: clock) {
            try await load.value
            return true
        }
        return finished == true ? nil : load
    }

    /// Records a load that ended without a model, answering the failure shown, or `nil` when a dictation kept it off.
    @discardableResult
    private func loadFailed(
        _ error: any Error, as failureClass: SpeechLoadFailureClass
    ) -> DictationFailure? {
        isReady = false
        lastLoadFailure = failureClass
        // Never over a dictation in progress: loading can run while the user speaks.
        guard !isBusy else { return nil }
        let failure = DictationFailure(error, speechEngineKind: speech.kind)
        transition(to: .failed(failure))
        return failure
    }

    /// Makes the model ready when a load past the limit ends, clearing the failure the limit put on screen.
    private func adopt(_ load: Task<Void, any Error>, replacing shown: DictationFailure?) {
        Task { [weak self] in
            do { try await load.value } catch { return }
            await self?.lateLoadEnded(replacing: shown)
        }
    }

    /// The model a late load brought in; the failure is cleared only if it is still the one the limit showed.
    private func lateLoadEnded(replacing shown: DictationFailure?) {
        isReady = true
        lastLoadFailure = nil
        guard case .failed(let failure) = state, failure == shown, !isBusy else { return }
        transition(to: .idle)
    }
}
