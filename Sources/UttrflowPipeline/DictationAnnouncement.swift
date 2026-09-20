// What VoiceOver says when a dictation starts, lands or fails.

/// One sentence for VoiceOver to speak unasked, since the floating button never takes focus.
public struct DictationAnnouncement: Sendable, Equatable {
    /// What is spoken; a glance at the words, never the whole dictation.
    public let text: String
    /// Whether it interrupts what VoiceOver is reading, which only a failure earns.
    public let isUrgent: Bool

    public init(text: String, isUrgent: Bool) {
        self.text = text
        self.isUrgent = isUrgent
    }
}

extension DictationPresenter {
    /// What to announce on arriving at `state`, or `nil` when the state is not news.
    public static func announcement(for state: DictationState) -> DictationAnnouncement? {
        switch state {
        // The wait is covered by the stop cue, and announcing it would talk over the result.
        case .idle, .transcribing, .tidying, .inserting:
            return nil

        case .recording:
            return DictationAnnouncement(text: "Listening.", isUrgent: false)

        case .inserted(let outcome) where outcome.method == .clipboard && outcome.isFromRecording:
            return DictationAnnouncement(
                text: "Copied to the clipboard. Press Command V to paste it. \(preview(of: outcome.text))",
                isUrgent: false)

        case .inserted(let outcome) where outcome.method == .clipboard:
            return DictationAnnouncement(
                text: "Copied to the clipboard, not typed. Press Command V to paste it. "
                    + "Uttrflow needs Accessibility access to type for you.",
                isUrgent: true)

        case .inserted(let outcome) where outcome.arrival == .unconfirmed:
            return DictationAnnouncement(
                text: "Inserted, but not confirmed. Press Command V if the words are missing.",
                isUrgent: false)

        case .inserted(let outcome):
            return DictationAnnouncement(text: "Inserted: \(preview(of: outcome.text))", isUrgent: false)

        case .failed(let failure):
            return DictationAnnouncement(
                text: failure.message.filter { $0 != "…" }, isUrgent: true)
        }
    }
}
