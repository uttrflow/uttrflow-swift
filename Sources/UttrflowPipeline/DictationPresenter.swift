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

        // Transcribing, tidying and the wait for the app to take the words are one wait, so one line.
        case .transcribing, .tidying, .inserting:
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
            // Nothing was typed, and saying "Inserted" here is what tells the user to press ⌘V.
            DockPresentation(
                symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V",
                secondaryLine: preview(of: outcome.text),
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: .openSystemSettings(.accessibility),
                accessibilityLabel:
                    "Copied to the clipboard, not typed. Press Command V to paste it. "
                    + "Uttrflow needs Accessibility access to type for you. \(outcome.text)")

        case .inserted(let outcome) where outcome.arrival == .unconfirmed:
            // The instruction is worth more than the glance here, since the words are still recoverable.
            DockPresentation(
                symbolName: "questionmark.circle", primaryLine: "Inserted — not confirmed",
                secondaryLine: "Still on the clipboard — press ⌘V if it is missing",
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel:
                    "Inserted, but not confirmed. The words are still on the clipboard, so press "
                    + "Command V if they are missing. \(outcome.text)")

        case .inserted(let outcome):
            DockPresentation(
                symbolName: "checkmark", primaryLine: "Inserted",
                secondaryLine: preview(of: outcome.text),
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: "Inserted: \(outcome.text)")

        // Drawn wide with its words, not as the quiet disc the other informational notice gets.
        case .failed(let failure) where failure == .stillLoading:
            DockPresentation(
                symbolName: "hourglass", primaryLine: failure.message, secondaryLine: nil,
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: failure.message.filter { $0 != "…" } + ".")

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

    /// The button with the speech model's load drawn in where it would otherwise rest or fall silent.
    public static func dock(
        for state: DictationState, advice: DictationAdvice = .keepGoing, speechModel: SpeechModelLoad?
    ) -> DockPresentation {
        let drawn = dock(for: state, advice: advice)
        // A missing model is setup's to fetch, and the button stays out of the way while setup runs.
        guard let load = speechModel, load != .missing else { return drawn }
        switch state {
        case .idle:
            return DockPresentation(
                symbolName: load.isLoading ? "hourglass" : "exclamationmark.triangle",
                primaryLine: load.line, secondaryLine: load.detail,
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: load.recovery, accessibilityLabel: load.accessibilityLabel)
        case .failed(let failure) where failure.transcript == nil:
            // The failure keeps its own line and button; the second line says why dictation cannot start.
            return DockPresentation(
                symbolName: drawn.symbolName, primaryLine: drawn.primaryLine,
                secondaryLine: load.detail, showsWaveform: false, showsProgress: false,
                isRecording: false, action: drawn.action,
                accessibilityLabel: failure == .stillLoading
                    ? load.accessibilityLabel : "\(drawn.accessibilityLabel) \(load.accessibilityLabel)")
        case .recording, .transcribing, .tidying, .inserting, .inserted, .failed:
            return drawn
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
