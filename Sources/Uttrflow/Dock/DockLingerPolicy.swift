import UttrflowPipeline

/// The retention interval for a completed dictation state, independent of windows and timers.
enum DockLingerPolicy {
    static let successLingers = Duration.seconds(2)
    static let failureLingers = Duration.seconds(10)
    static let voiceOverFailureLingers = Duration.seconds(20)

    /// How long a finished state stays up, or `nil` for a state that is not finished.
    static func linger(after state: DictationState, voiceOverEnabled: Bool = false) -> Duration? {
        switch state {
        // Copied rather than typed asks the user to paste, so it stays as long as a failure.
        case .inserted(let outcome) where outcome.method == .clipboard: failureLingers
        case .inserted: successLingers
        // An informational notice asks nothing of the user, so it goes sooner.
        case .failed(let notice):
            if notice.severity == .informational {
                successLingers
            } else if voiceOverEnabled, notice.recovery != nil {
                voiceOverFailureLingers
            } else {
                failureLingers
            }
        // A Restore on offer stays as long as a failure's button; with nothing to offer it goes sooner.
        case .discarded(let discard): discard.keptRecording == nil ? successLingers : failureLingers
        case .executed: successLingers
        case .idle, .recording, .transcribing, .tidying, .inserting: nil
        }
    }
}
