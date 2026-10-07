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
    /// The speech model's setup, drawn in its own form while the button rests; absent once it can transcribe.
    public var setup: DockModelSetup? = nil
}

/// The speech model's state as the resting button draws it.
public enum DockModelSetup: Sendable, Equatable {
    /// Downloading, at a share from 0 to 1.
    case downloading(Double)
    /// On disk and loading into memory, with the estimated share once the load has run long enough to have one.
    case loading(Double?)
    /// The load ended without a model that can transcribe.
    case failed
    /// Incomplete, or failed to load twice, so it must be downloaded again.
    case broken
    /// Not on disk.
    case missing

    /// The words on the form's one button, or `nil` for a form with nothing to press.
    public var actionTitle: String? {
        switch self {
        case .downloading, .loading: nil
        case .failed: "Retry"
        case .broken, .missing: "Download"
        }
    }

    /// A share as a whole percentage, clamped to 0 through 100.
    public static func percentage(of fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }
}

/// Turns the pipeline's state into what the floating button draws; never names an engine (§16).
public enum DictationPresenter {
    /// The microphone time as "0:04" or "1:23"; minutes keep counting past an hour, never rolling over.
    public static func elapsed(_ duration: Duration) -> String {
        let seconds = max(Int(duration.components.seconds), 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    /// A passing notice about something other than a dictation, drawn like an outcome: words, no waveform, no action.
    public static func dock(
        notice symbolName: String, primaryLine: String, secondaryLine: String?,
        accessibilityLabel: String
    ) -> DockPresentation {
        DockPresentation(
            symbolName: symbolName, primaryLine: primaryLine, secondaryLine: secondaryLine,
            showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
            accessibilityLabel: accessibilityLabel)
    }

    /// `waited` is the time since key release, which names the stage once the wait runs long.
    public static func dock(
        for state: DictationState, advice: DictationAdvice = .keepGoing,
        stopGesture: StopGesture = .letGo, heardSoFar: String? = nil, waited: Duration = .zero
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
                symbolName: "mic.fill", primaryLine: stopGesture.recordingLine,
                // The time left outranks the words, which are already safe in the recording.
                secondaryLine: RemainingTime.phrase(for: advice) ?? heardSoFar.map { latest(of: $0) },
                showsWaveform: true, showsProgress: false, isRecording: true, action: nil,
                accessibilityLabel: RemainingTime.phrase(for: advice)
                    .map { "\(stopGesture.recordingAccessibilityPrefix). \($0)." }
                    ?? "\(stopGesture.recordingAccessibilityPrefix).")

        // One animation throughout; the line names the stage only once the wait has run long.
        case .transcribing, .tidying, .inserting:
            working(WaitLine.stage(of: state, waited: waited), waited: waited)

        case .inserted(let outcome) where outcome.method == .clipboard && outcome.isFromRecording:
            DockPresentation(
                symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V",
                secondaryLine: outcome.wordsToKeep.map { preview(of: $0) },
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel:
                    "Copied to the clipboard. Press Command V to paste it.\(missing(outcome)) \(said(outcome))"
            )

        case .inserted(let outcome) where outcome.method == .clipboard:
            // Nothing was typed, and saying "Inserted" here is what tells the user to press ⌘V.
            DockPresentation(
                symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V",
                secondaryLine: outcome.wordsToKeep.map { preview(of: $0) },
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: .openSystemSettings(.accessibility),
                accessibilityLabel:
                    "Copied to the clipboard, not typed. Press Command V to paste it. "
                    + "Uttrflow needs Accessibility access to type for you.\(missing(outcome)) \(said(outcome))"
            )

        case .inserted(let outcome) where outcome.arrival == .unconfirmed:
            // The instruction is worth more than the glance here, since the words are still recoverable.
            DockPresentation(
                symbolName: "questionmark.circle", primaryLine: "Inserted — not confirmed",
                secondaryLine: "Still on the clipboard — press ⌘V if it is missing",
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel:
                    "Inserted, but not confirmed. The words are still on the clipboard, so press "
                    + "Command V if they are missing.\(missing(outcome)) \(said(outcome))")

        case .inserted(let outcome) where MissedSpeech.isMissing(outcome.missedPieces):
            DockPresentation(
                symbolName: "exclamationmark.circle", primaryLine: MissedSpeech.line,
                secondaryLine: MissedSpeech.detail,
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: "Inserted. \(MissedSpeech.sentence) \(said(outcome))")

        case .inserted(let outcome):
            DockPresentation(
                symbolName: "checkmark", primaryLine: "Inserted",
                secondaryLine: outcome.wordsToKeep.map { preview(of: $0) },
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: "Inserted: \(said(outcome))")

        case .discarded(let discard):
            DockPresentation(
                symbolName: "trash", primaryLine: "Discarded",
                secondaryLine: discard.keptRecording == nil ? "Nothing was typed" : "Restore within a minute",
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: discard.keptRecording == nil ? nil : .restoreRecording,
                accessibilityLabel: discard.keptRecording == nil
                    ? "Discarded. Nothing was typed."
                    : "Discarded. Nothing was typed. Restore within a minute.")

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
                secondaryLine: failure.wordsToKeep.map { Self.preview(of: $0) },
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: failure.recovery,
                accessibilityLabel: failure.message)
        }
    }

    /// The working orb, with the stage's words and, past `WaitLine.secondsAfter`, the seconds waited.
    static func working(_ stage: String?, waited: Duration) -> DockPresentation {
        guard let stage else {
            return DockPresentation(
                symbolName: "sparkles", primaryLine: "Tidying up…", secondaryLine: nil,
                showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
                accessibilityLabel: "Working on what you said.")
        }
        return DockPresentation(
            symbolName: "sparkles", primaryLine: "\(stage)…",
            secondaryLine: waited >= WaitLine.secondsAfter ? elapsed(waited) : nil,
            showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
            accessibilityLabel: "\(stage).")
    }

    /// The button with the speech model's download or load drawn in where it would otherwise rest or fall silent.
    public static func dock(
        for state: DictationState, advice: DictationAdvice = .keepGoing, speechModel: SpeechModelLoad?,
        download: Double? = nil, stopGesture: StopGesture = .letGo, heardSoFar: String? = nil,
        waited: Duration = .zero
    ) -> DockPresentation {
        let drawn = dock(
            for: state, advice: advice, stopGesture: stopGesture, heardSoFar: heardSoFar, waited: waited)
        if case .idle = state, let download { return resting(downloading: download) }
        guard let load = speechModel else { return drawn }
        switch state {
        case .idle:
            return resting(load)
        case .failed(let failure) where failure.transcript == nil && load != .missing:
            // The failure keeps its own line and button; the second line says why dictation cannot start.
            return DockPresentation(
                symbolName: drawn.symbolName, primaryLine: drawn.primaryLine,
                secondaryLine: load.detail, showsWaveform: false, showsProgress: false,
                isRecording: false, action: drawn.action,
                accessibilityLabel: failure == .stillLoading
                    ? load.accessibilityLabel : "\(drawn.accessibilityLabel) \(load.accessibilityLabel)")
        case .recording, .transcribing, .tidying, .inserting, .inserted, .failed, .discarded:
            return drawn
        }
    }

    /// Resting while the speech model downloads: a ring filling to the share done.
    static func resting(downloading fraction: Double) -> DockPresentation {
        let percent = DockModelSetup.percentage(of: fraction)
        return DockPresentation(
            symbolName: "arrow.down.circle", primaryLine: "Setting up", secondaryLine: "\(percent)%",
            showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
            accessibilityLabel: "Setting up. Downloading the speech model, \(percent) percent.",
            setup: .downloading(min(max(fraction, 0), 1)))
    }

    /// Resting while the speech model loads, after it failed to, or while it is not on disk.
    static func resting(_ load: SpeechModelLoad) -> DockPresentation {
        switch load {
        case .loading:
            // A spinner for the first seconds, then a ring filled to the estimate beside the time left.
            DockPresentation(
                symbolName: "hourglass", primaryLine: dockLine(for: load.estimate),
                secondaryLine: load.estimate.flatMap { $0.isHolding ? nil : $0.shortTimeLeft },
                showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                accessibilityLabel: load.accessibilityLabel, setup: .loading(load.estimate?.fraction))
        case .failed:
            DockPresentation(
                symbolName: "exclamationmark.triangle", primaryLine: load.line, secondaryLine: load.detail,
                showsWaveform: false, showsProgress: false, isRecording: false, action: .retry,
                accessibilityLabel:
                    "The speech model didn’t load. Dictation can’t start without it. Try loading it again.",
                setup: .failed)
        case .broken:
            DockPresentation(
                symbolName: "exclamationmark.triangle", primaryLine: load.line, secondaryLine: load.detail,
                showsWaveform: false, showsProgress: false, isRecording: false,
                action: .downloadSpeechModel, accessibilityLabel: load.accessibilityLabel, setup: .broken)
        case .missing:
            DockPresentation(
                symbolName: "exclamationmark.triangle", primaryLine: "Speech model needed",
                secondaryLine: load.detail, showsWaveform: false, showsProgress: false,
                isRecording: false, action: .downloadSpeechModel,
                accessibilityLabel: load.accessibilityLabel, setup: .missing)
        }
    }

    /// "Getting ready…" before the estimate, "Getting ready" beside one, and "Almost ready" once it holds.
    static func dockLine(for estimate: SpeechModelLoadEstimate?) -> String {
        guard let estimate else { return "Getting ready…" }
        return estimate.isHolding ? "Almost ready" : "Getting ready"
    }

    /// The words read aloud with the notice, withheld when the field is secure or they look like a credential.
    static func said(_ outcome: DictationOutcome) -> String {
        outcome.wordsToKeep
            ?? (outcome.intoSecureField
                ? "The words are hidden because the field is secure."
                : "The words are hidden because they look like a password or key.")
    }

    /// The missing-speech sentence with its leading space, or nothing when every piece decoded.
    static func missing(_ outcome: DictationOutcome) -> String {
        MissedSpeech.isMissing(outcome.missedPieces) ? " \(MissedSpeech.sentence)" : ""
    }

    /// A glance at the text, since the floating button sits over the user's work.
    static func preview(of text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit).trimmingSuffixWhitespace() + "…"
    }

    /// The newest words of a growing text, since the panel follows speech as it is finished.
    static func latest(of text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        let tail = collapsed.suffix(limit)
        // Starts on a whole word, so the glance never opens mid-word.
        let start = tail.firstIndex(of: " ").map { tail.index(after: $0) } ?? tail.startIndex
        return "…" + tail[start...]
    }
}

extension Substring {
    fileprivate func trimmingSuffixWhitespace() -> String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }
}
