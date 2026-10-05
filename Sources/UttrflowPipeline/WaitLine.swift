// When the wait after key release stops being one unlabelled line and names its stage. See Docs/app-dock.md.

/// The stage words drawn once the wait after key release outlasts a short dictation's.
public enum WaitLine {
    /// The current p95 wait for a 5 s dictation is 9.5 s and for a 30 s one 14.0 s; see Docs/performance.md.
    public static let stageAfter = Duration.seconds(10)

    /// About the 30 s dictation's budget, 16.8 s, after which the seconds waited are drawn too.
    public static let secondsAfter = Duration.seconds(20)

    /// The stage's words, or nil while the wait is short enough for the one line every stage shares.
    public static func stage(of state: DictationState, waited: Duration) -> String? {
        guard waited >= stageAfter else { return nil }
        switch state {
        case .transcribing: return "Transcribing"
        case .tidying: return "Tidying"
        case .inserting(let app): return "Waiting for \(app ?? "the app")"
        case .idle, .recording, .inserted, .failed: return nil
        }
    }

    /// What VoiceOver says once, when the line first changes from the shared one to a stage.
    public static func announcement(
        for state: DictationState, waited: Duration, alreadyAnnounced: Bool
    ) -> DictationAnnouncement? {
        guard !alreadyAnnounced, let stage = stage(of: state, waited: waited) else { return nil }
        return DictationAnnouncement(text: "\(stage).", isUrgent: false)
    }
}
