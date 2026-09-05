public import UttrflowCore

/// What the floating button should show.
public struct DockPresentation: Sendable, Equatable {
    /// SF Symbol for the resting and hovered forms.
    public let symbolName: String
    /// The line of text beside it, if any. Absent when the button is a bare grip.
    public let primaryLine: String?
    /// The quieter second line — what was inserted, or why nothing was.
    public let secondaryLine: String?
    public let showsWaveform: Bool
    public let showsProgress: Bool
    /// Whether a recording indicator should be lit.
    public let isRecording: Bool
    /// Offered alongside a failure the user can do something about.
    public let action: RecoveryAction?
    /// Read aloud by VoiceOver. Never abbreviated, never an icon name.
    public let accessibilityLabel: String
}

/// Turns the pipeline's state into what the floating button draws.
///
/// Pure, and deliberately separate from any view: having one place decide what a state
/// looks like means the button and VoiceOver can never disagree about what is
/// happening. The menu bar is drawn from `MenuBarPresenter` in `UttrflowUX`, which sees
/// more than a dictation's state — the speech model, the recent dictations, and a
/// failure that has already been through `FailurePresenter`.
///
/// It is also where §16 lives — the user must never learn which engine ran. No string
/// produced here names a model, an engine or a file, and a test enforces that.
public enum DictationPresenter {
    /// How long the microphone has been open, as the button writes it: "0:04", "1:23".
    ///
    /// Minutes and seconds, never hours: a dictation is a sentence, and a clock reading
    /// "0:00:04" belongs to a stopwatch. Anything past an hour keeps counting in minutes
    /// rather than rolling over, because a button that says "0:04" after sixty-four
    /// minutes of a stuck recording would be hiding the very thing worth noticing.
    public static func elapsed(_ duration: Duration) -> String {
        let seconds = max(Int(duration.components.seconds), 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    public static func dock(
        for state: DictationState, advice: DictationAdvice = .keepGoing
    ) -> DockPresentation {
        switch state {
        case .idle:
            DockPresentation(
                symbolName: "mic", primaryLine: nil, secondaryLine: nil,
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: "Uttrflow. Ready to listen.")

        case .recording:
            DockPresentation(
                // What to do rather than what is happening: the waveform and the
                // recording light already say it is listening, and the one thing
                // somebody holding a key down needs told is how to stop.
                symbolName: "mic.fill", primaryLine: "Let go to finish",
                secondaryLine: RemainingTime.phrase(for: advice),
                showsWaveform: true, showsProgress: false, isRecording: true, action: nil,
                accessibilityLabel: RemainingTime.phrase(for: advice)
                    .map { "Listening. Let go to finish. \($0)." }
                    ?? "Listening. Let go to finish.")

        // Transcribing and tidying are one wait to the person waiting. Naming them
        // separately would describe the machinery rather than the moment.
        case .transcribing, .tidying:
            DockPresentation(
                symbolName: "sparkles", primaryLine: "Tidying up…", secondaryLine: nil,
                showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
                accessibilityLabel: "Working on what you said.")

        case .inserted(let outcome) where outcome.method == .clipboard && outcome.isFromRecording:
            DockPresentation(
                symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V",
                secondaryLine: preview(of: outcome.text),
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: "Copied to the clipboard. Press Command V to paste it. \(outcome.text)")

        case .inserted(let outcome) where outcome.method == .clipboard:
            // Nothing was typed. Saying "Inserted" here is the difference between a
            // user pressing ⌘V and a user believing the app is broken because their
            // words never appeared — which is exactly what it looked like.
            DockPresentation(
                symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V",
                secondaryLine: preview(of: outcome.text),
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: .openSystemSettings(.accessibility),
                accessibilityLabel:
                    "Copied to the clipboard, not typed. Press Command V to paste it. "
                    + "Uttrflow needs Accessibility access to type for you. \(outcome.text)")

        case .inserted(let outcome):
            DockPresentation(
                symbolName: "checkmark", primaryLine: "Inserted",
                secondaryLine: preview(of: outcome.text),
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: "Inserted: \(outcome.text)")

        case .failed(let failure):
            DockPresentation(
                // A warning triangle over "Didn't catch that" tells the user something
                // went wrong, when nothing did — they were not heard, which is worth
                // saying and is not an alarm. The design draws this severity softly for
                // that reason, so the badge has to follow it.
                symbolName: failure.severity == .informational
                    ? "waveform.slash" : "exclamationmark.triangle",
                primaryLine: failure.message,
                secondaryLine: failure.transcript.map { Self.preview(of: $0) },
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: failure.recovery,
                accessibilityLabel: failure.message)
        }
    }

    /// A glance at the text, not the whole of it.
    ///
    /// The floating button sits over the user's work; a long dictation would cover it.
    static func preview(of text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit).trimmingSuffixWhitespace() + "…"
    }
}

extension Substring {
    fileprivate func trimmingSuffixWhitespace() -> String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }
}
