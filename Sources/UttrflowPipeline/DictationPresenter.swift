// Turns the pipeline's state into what the floating button draws.
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

/// Turns the pipeline's state into what the floating button draws; never names an engine (§16).
public enum DictationPresenter {
    /// The microphone time as "0:04" or "1:23"; minutes keep counting past an hour, never rolling over.
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
                // Says what to do, not what is happening: the waveform already says it is listening.
                symbolName: "mic.fill", primaryLine: "Let go to finish",
                secondaryLine: RemainingTime.phrase(for: advice),
                showsWaveform: true, showsProgress: false, isRecording: true, action: nil,
                accessibilityLabel: RemainingTime.phrase(for: advice)
                    .map { "Listening. Let go to finish. \($0)." }
                    ?? "Listening. Let go to finish.")

        // Transcribing and tidying are one wait to the person waiting.
        case .transcribing, .tidying:
            DockPresentation(
                symbolName: "sparkles", primaryLine: "Tidying up…", secondaryLine: nil,
                showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
                accessibilityLabel: "Working on what you said.")

        // Still working as far as the person waiting is concerned: nothing is on their screen yet.
        case .inserting:
            DockPresentation(
                symbolName: "sparkles", primaryLine: "Putting it in…", secondaryLine: nil,
                showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
                accessibilityLabel: "Putting your words in.")

        case .inserted(let outcome) where outcome.method == .clipboard && outcome.isFromRecording:
            DockPresentation(
                symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V",
                secondaryLine: preview(of: outcome.text),
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: "Copied to the clipboard. Press Command V to paste it. \(outcome.text)")

        case .inserted(let outcome) where outcome.method == .clipboard:
            // Nothing was typed, and saying "Inserted" here is what tells the user to press ⌘V.
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
                // "Didn't catch that" is not an alarm, so the badge follows the softer severity.
                symbolName: failure.severity == .informational
                    ? "waveform.slash" : "exclamationmark.triangle",
                primaryLine: failure.message,
                secondaryLine: failure.transcript.map { Self.preview(of: $0) },
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: failure.recovery,
                accessibilityLabel: failure.message)
        }
    }

    /// A glance at the text, since the floating button sits over the user's work.
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
