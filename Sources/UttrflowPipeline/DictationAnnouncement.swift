// What VoiceOver says when a dictation starts, lands or fails.
public import UttrflowCore

/// One sentence for VoiceOver to speak unasked, since the floating button never takes focus.
public struct DictationAnnouncement: Sendable, Equatable {
    /// What is spoken; the words only as far as `DictationReadBack` allows.
    public let text: String
    /// Whether it interrupts what VoiceOver is reading, which only a failure earns.
    public let isUrgent: Bool

    public init(text: String, isUrgent: Bool) {
        self.text = text
        self.isUrgent = isUrgent
    }
}

extension DictationPresenter {
    /// What to announce once when a recording first reaches its warning point.
    public static func warningAnnouncement(for advice: DictationAdvice) -> DictationAnnouncement? {
        guard let remaining = RemainingTime.phrase(for: advice) else { return nil }
        return DictationAnnouncement(text: "Dictation ends soon. \(remaining).", isUrgent: false)
    }

    /// What to announce on arriving at `state`, or `nil` when the state is not news.
    public static func announcement(
        for state: DictationState, readBack: DictationReadBack = .preview
    ) -> DictationAnnouncement? {
        switch state {
        // The wait is covered by the stop cue, and announcing it would talk over the result.
        case .idle, .transcribing, .tidying, .inserting:
            return nil

        case .recording:
            return DictationAnnouncement(text: "Listening.", isUrgent: false)

        case .inserted(let outcome) where outcome.method == .clipboard && outcome.isFromRecording:
            return DictationAnnouncement(
                text: "Copied to the clipboard. Press Command V to paste it.\(missing(outcome))"
                    + (readBack.spoken(outcome).map { " " + $0 } ?? ""),
                isUrgent: false)

        case .inserted(let outcome) where outcome.method == .clipboard:
            return DictationAnnouncement(
                text: "Copied to the clipboard, not typed. Press Command V to paste it. "
                    + "Uttrflow needs Accessibility access to type for you.\(missing(outcome))",
                isUrgent: true)

        case .inserted(let outcome) where outcome.arrival == .unconfirmed:
            return DictationAnnouncement(
                text: "Inserted, but not confirmed. Press Command V if the words are missing."
                    + missing(outcome),
                isUrgent: false)

        case .inserted(let outcome) where MissedSpeech.isMissing(outcome.missedPieces):
            return DictationAnnouncement(
                text: "Inserted. \(MissedSpeech.sentence)"
                    + (readBack.spoken(outcome).map { " " + $0 } ?? ""),
                isUrgent: false)

        case .inserted(let outcome):
            return DictationAnnouncement(
                text: readBack.spoken(outcome).map { "Inserted: \($0)" } ?? "Inserted.", isUrgent: false)

        case .failed(let failure):
            let message = failure.message.filter { $0 != "…" }
            guard let recovery = failure.recovery else {
                return DictationAnnouncement(text: message, isUrgent: true)
            }
            return DictationAnnouncement(
                text: "\(message) \(recovery.instruction)", isUrgent: true)
        }
    }
}

/// Plays and announces the single warning event, keeping both user cues on the same production path.
public struct DictationWarningReporter: Sendable {
    private let cue: any RecordingCueing
    private let announce: @Sendable (DictationAnnouncement) -> Void

    public init(
        cue: any RecordingCueing,
        announce: @escaping @Sendable (DictationAnnouncement) -> Void
    ) {
        self.cue = cue
        self.announce = announce
    }

    /// Plays the distinct warning cue and announces the remaining time without interrupting VoiceOver.
    public func report(_ advice: DictationAdvice) {
        guard let announcement = DictationPresenter.warningAnnouncement(for: advice) else { return }
        cue.playWarning()
        announce(announcement)
    }
}

private extension RecoveryAction {
    /// Where VoiceOver users can reach the recovery offered on the floating button.
    var instruction: String {
        switch self {
        case .openSystemSettings:
            "Open Settings from the Uttrflow menu."
        case .retry:
            "Choose Try Again from the Uttrflow menu."
        case .downloadSpeechModel:
            "Choose Download from the Uttrflow menu."
        case .pasteManually:
            "The text is on your clipboard. Press Command V to paste it."
        case .showHistory:
            "Open History from the Uttrflow menu to find your words."
        case .copyTranscript:
            "Choose Copy on the floating button to copy your words."
        case .retryFromRecording:
            "Open History from the Uttrflow menu, then choose Retry on the recording."
        }
    }
}
