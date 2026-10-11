import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

/// Clears the running loop's learned state while its existing write barriers remain closed.
@MainActor
struct SuggestionForgetting {
    let capture: CaptureSession
    let store: PredictStore
    let rejectedSuggestionRecorder: RejectedSuggestionRecorder
    let acceptances: AcceptanceQueue
    let verifier: Verifier

    /// Removes one application's learned lines, preserving every recorded capture answer.
    func forgetSuggestions(from bundleIdentifier: String, completed: () -> Void) async throws {
        let capture = self.capture
        let store = self.store
        try await forgetWhatThisLoopRemembers(
            of: bundleIdentifier,
            clearingCorpus: {
                await capture.forgetLearned(from: bundleIdentifier)
                try await store.forget(bundleIdentifier: bundleIdentifier)
            }, completed: completed)
    }

    /// Removes every learned line before removing the capture answers.
    func forgetEverySuggestion(completed: () -> Void) async throws {
        let capture = self.capture
        let store = self.store
        try await forgetWhatThisLoopRemembers(
            of: nil,
            clearingCorpus: {
                await capture.forgetLearnedLines()
                try await store.forgetEverything()
                try await capture.forgetEveryAnswer()
            }, completed: completed)
    }

    /// Drops the verdicts, model answers and held rejections this loop keeps for one application, or for all when nil.
    private func forgetWhatThisLoopRemembers(
        of bundleIdentifier: String?, clearingCorpus: @escaping @Sendable () async throws -> Void,
        completed: () -> Void
    ) async throws {
        rejectedSuggestionRecorder.forget(bundleIdentifier: bundleIdentifier)
        await acceptances.beginForgetting()
        defer { acceptances.finishForgetting() }
        try await verifier.forgetEverything(then: clearingCorpus)
        completed()
    }
}
