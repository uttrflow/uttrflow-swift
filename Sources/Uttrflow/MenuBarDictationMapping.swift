import UttrflowCore
import UttrflowPipeline
import UttrflowUX

/// Projects dictation activity, quality and failure onto the menu independently of app coordination.
enum MenuBarDictationMapping {
    nonisolated static func state(
        for state: DictationState, floatingButtonShown: Bool
    ) -> MenuBarState {
        let activity: DictationActivity =
            switch state {
            case .idle, .failed: .idle
            case .discarded: .discarded
            case .executed: .executed
            case .recording: .listening
            case .transcribing, .tidying, .inserting: .working
            case .inserted(let outcome):
                DictationActivity.completion(
                    method: outcome.method, arrival: outcome.arrival, quality: outcome.quality)
            }
        var failure: FailurePresentation?
        if case .failed(let notice) = state {
            failure = FailurePresenter.present(
                message: notice.message, recovery: notice.recovery, severity: notice.severity,
                floatingButtonShown: floatingButtonShown)
        }
        var quality = OutcomeQuality.complete
        if case .inserted(let outcome) = state { quality = outcome.quality }
        return MenuBarState(activity: activity, outcomeQuality: quality, failure: failure)
    }
}
