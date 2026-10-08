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
    /// What to announce when a tap lands too late to pair with the one before it, so it is not discarded in silence.
    public static let nearMissTapAnnouncement = DictationAnnouncement(
        text: "Tap too slow, double-tap faster", isUrgent: false)

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

        case .discarded(let discard):
            guard discard.keptRecording != nil else {
                return DictationAnnouncement(text: "Discarded. Nothing was typed.", isUrgent: false)
            }
            return DictationAnnouncement(
                text: "Discarded. Nothing was typed. \(RecoveryAction.restoreRecording.instruction)",
                isUrgent: false)

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

    /// Plays the distinct warning cue, and speaks the remaining time only when that cue is not heard.
    public func report(_ advice: DictationAdvice) {
        guard let announcement = DictationPresenter.warningAnnouncement(for: advice) else { return }
        // The microphone is open, so a heard cue carries the warning and spoken words would be recorded.
        let heard = cue.isAudible
        cue.playWarning()
        guard !heard else { return }
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
        case .restoreRecording:
            "To get the words back within a minute, open History from the Uttrflow menu and choose Retry."
        }
    }
}

/// Announces dictation states, saying "Listening." once for a double tap whose first tap reopened the microphone.
public struct DictationAnnouncer<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration {
    /// How soon a reopened microphone counts as the same start: the double-tap window the controller uses.
    public var repeatWindow: Duration
    private var lastListening: Instant?

    public init(repeatWindow: Duration) {
        self.repeatWindow = repeatWindow
    }

    /// What to announce on arriving at `state` at `now`; `nil` when it is not news, a repeat "Listening.", or a heard start cue.
    public mutating func announcement(
        for state: DictationState, at now: Instant, readBack: DictationReadBack = .preview,
        startCueHeard: Bool = false
    ) -> DictationAnnouncement? {
        let said = DictationPresenter.announcement(for: state, readBack: readBack)
        guard state == .recording else {
            if said != nil { lastListening = nil }
            return said
        }
        defer { lastListening = now }
        if startCueHeard { return nil }
        if let last = lastListening, last.duration(to: now) < repeatWindow { return nil }
        return said
    }
}

/// Holds VoiceOver's lines while the microphone is open, so the recording never hears them. See `Docs/audio-capture.md`.
public struct AnnouncementHold: Sendable {
    private var microphoneOpen = false
    private var held: [DictationAnnouncement] = []

    public init() {}

    /// `line` to speak now, or `nil` when it waits for the microphone to close.
    public mutating func offer(_ line: DictationAnnouncement) -> DictationAnnouncement? {
        guard microphoneOpen else { return line }
        held.append(line)
        return nil
    }

    /// Follows the microphone; closing it hands back every held line, oldest first.
    public mutating func microphone(isOpen: Bool) -> [DictationAnnouncement] {
        microphoneOpen = isOpen
        guard !isOpen else { return [] }
        defer { held.removeAll() }
        return held
    }
}
