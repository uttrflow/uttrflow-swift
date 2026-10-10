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

extension DockPresentation {
    /// A badge with words beside it, or none, and nothing moving: an outcome, a failure or the model's setup.
    static func notice(
        _ symbolName: String, _ primaryLine: String?, _ secondaryLine: String?,
        action: RecoveryAction? = nil, label: String
    ) -> DockPresentation {
        DockPresentation(
            symbolName: symbolName, primaryLine: primaryLine, secondaryLine: secondaryLine,
            showsWaveform: false, showsProgress: false, isRecording: false, action: action,
            accessibilityLabel: label)
    }

    /// The lit microphone with its waveform, while the user speaks.
    static func listening(_ primaryLine: String, _ secondaryLine: String?, label: String) -> DockPresentation
    {
        DockPresentation(
            symbolName: "mic.fill", primaryLine: primaryLine, secondaryLine: secondaryLine,
            showsWaveform: true, showsProgress: false, isRecording: true, action: nil,
            accessibilityLabel: label)
    }

    /// The working orb, while the words are transcribed, tidied and inserted.
    static func working(_ primaryLine: String, _ secondaryLine: String?, label: String) -> DockPresentation {
        DockPresentation(
            symbolName: "sparkles", primaryLine: primaryLine, secondaryLine: secondaryLine,
            showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
            accessibilityLabel: label)
    }

    /// The same presentation drawn in the speech model's setup form.
    func settingUp(_ setup: DockModelSetup) -> DockPresentation {
        var drawn = self
        drawn.setup = setup
        return drawn
    }
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
        .notice(symbolName, primaryLine, secondaryLine, label: accessibilityLabel)
    }

    /// `waited` is the time since key release, which names the stage once the wait runs long.
    public static func dock(
        for state: DictationState, advice: DictationAdvice = .keepGoing,
        stopGesture: StopGesture = .letGo, heardSoFar: String? = nil, waited: Duration = .zero
    ) -> DockPresentation {
        switch state {
        case .idle: .notice("mic", nil, nil, label: "Uttrflow. Ready to listen.")
        case .recording: listening(advice: advice, stopGesture: stopGesture, heardSoFar: heardSoFar)
        // One animation throughout; the line names the stage only once the wait has run long.
        case .transcribing, .tidying, .inserting:
            working(WaitLine.stage(of: state, waited: waited), waited: waited)
        case .inserted(let outcome): insertedNotice(outcome)
        case .discarded(let discard): discardedNotice(discard)
        case .executed(let said): .notice("checkmark", said, nil, label: said)
        case .failed(let failure): failureNotice(failure)
        }
    }

    /// The lit microphone, saying what to do rather than what is happening, since the waveform already says it.
    static func listening(
        advice: DictationAdvice, stopGesture: StopGesture, heardSoFar: String?
    ) -> DockPresentation {
        let remaining = RemainingTime.phrase(for: advice)
        let prefix = stopGesture.recordingAccessibilityPrefix
        return .listening(
            stopGesture.recordingLine,
            // The time left outranks the words, which are already safe in the recording.
            remaining ?? heardSoFar.map { latest(of: $0) },
            label: remaining.map { "\(prefix). \($0)." } ?? "\(prefix).")
    }

    /// The working orb, with the stage's words and, past `WaitLine.secondsAfter`, the seconds waited.
    static func working(_ stage: String?, waited: Duration) -> DockPresentation {
        guard let stage else { return .working("Tidying up…", nil, label: "Working on what you said.") }
        return .working(
            "\(stage)…", waited >= WaitLine.secondsAfter ? elapsed(waited) : nil, label: "\(stage).")
    }

    /// What the button says once the words have gone in, or onto the clipboard instead.
    static func insertedNotice(_ outcome: DictationOutcome) -> DockPresentation {
        if outcome.method == .clipboard { return copiedNotice(outcome) }
        if outcome.arrival == .unconfirmed {
            // The instruction is worth more than the glance here, since the words are still recoverable.
            return .notice(
                "questionmark.circle", "Inserted — not confirmed",
                "Still on the clipboard — press ⌘V if it is missing",
                label: "Inserted, but not confirmed. The words are still on the clipboard, so press "
                    + "Command V if they are missing.\(missing(outcome)) \(said(outcome))")
        }
        if MissedSpeech.isMissing(outcome.missedPieces) {
            return .notice(
                "exclamationmark.circle", MissedSpeech.line, MissedSpeech.detail,
                label: "Inserted. \(MissedSpeech.sentence) \(said(outcome))")
        }
        return .notice(
            "checkmark", "Inserted", outcome.wordsToKeep.map { preview(of: $0) },
            label: "Inserted: \(said(outcome))")
    }

    /// Copied rather than typed; from the microphone, saying "Inserted" here would hide that ⌘V is needed.
    static func copiedNotice(_ outcome: DictationOutcome) -> DockPresentation {
        let label =
            outcome.isFromRecording
            ? "Copied to the clipboard. Press Command V to paste it."
            : "Copied to the clipboard, not typed. Press Command V to paste it. "
                + "Uttrflow needs Accessibility access to type for you."
        return .notice(
            "doc.on.clipboard", "Copied — press ⌘V", outcome.wordsToKeep.map { preview(of: $0) },
            action: outcome.isFromRecording ? nil : .openSystemSettings(.accessibility),
            label: "\(label)\(missing(outcome)) \(said(outcome))")
    }

    /// A cancelled recording, offering Restore while its audio is kept.
    static func discardedNotice(_ discard: DictationDiscard) -> DockPresentation {
        guard discard.keptRecording != nil else {
            return .notice("trash", "Discarded", "Nothing was typed", label: "Discarded. Nothing was typed.")
        }
        return .notice(
            "trash", "Discarded", "Restore within a minute", action: .restoreRecording,
            label: "Discarded. Nothing was typed. Restore within a minute.")
    }

    /// The failure's own sentence and recovery, keeping a glance at any words it saved.
    static func failureNotice(_ failure: DictationFailure) -> DockPresentation {
        // Drawn wide with its words, not as the quiet disc the other informational notice gets.
        if failure == .stillLoading {
            return .notice(
                "hourglass", failure.message, nil, label: failure.message.filter { $0 != "…" } + ".")
        }
        return .notice(
            // "Didn't catch that" is not an alarm, so the badge follows the softer severity.
            failure.severity == .informational ? "waveform.slash" : "exclamationmark.triangle",
            failure.message, failure.wordsToKeep.map { preview(of: $0) }, action: failure.recovery,
            label: failure.message)
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
            return .notice(
                drawn.symbolName, drawn.primaryLine, load.detail, action: drawn.action,
                label: failure == .stillLoading
                    ? load.accessibilityLabel : "\(drawn.accessibilityLabel) \(load.accessibilityLabel)")
        case .recording, .transcribing, .tidying, .inserting, .inserted, .failed, .executed, .discarded:
            return drawn
        }
    }

    /// Resting while the speech model downloads: a ring filling to the share done.
    static func resting(downloading fraction: Double) -> DockPresentation {
        let percent = DockModelSetup.percentage(of: fraction)
        return .notice(
            "arrow.down.circle", "Setting up", "\(percent)%",
            label: "Setting up. Downloading the speech model, \(percent) percent."
        ).settingUp(.downloading(min(max(fraction, 0), 1)))
    }

    /// Resting while the speech model loads, after it failed to, or while it is not on disk.
    static func resting(_ load: SpeechModelLoad) -> DockPresentation {
        switch load {
        case .loading:
            // A spinner for the first seconds, then a ring filled to the estimate beside the time left.
            .notice(
                "hourglass", dockLine(for: load.estimate),
                load.estimate.flatMap { $0.isHolding ? nil : $0.shortTimeLeft },
                label: load.accessibilityLabel
            ).settingUp(.loading(load.estimate?.fraction))
        case .failed:
            .notice(
                "exclamationmark.triangle", load.line, load.detail, action: .retry,
                label: "The speech model didn’t load. Dictation can’t start without it. Try loading it again."
            ).settingUp(.failed)
        case .broken:
            .notice(
                "exclamationmark.triangle", load.line, load.detail, action: .downloadSpeechModel,
                label: load.accessibilityLabel
            ).settingUp(.broken)
        case .missing:
            .notice(
                "exclamationmark.triangle", "Speech model needed", load.detail, action: .downloadSpeechModel,
                label: load.accessibilityLabel
            ).settingUp(.missing)
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
        let collapsed = WordTokens.words(text, .display).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit).trimmingSuffixWhitespace() + "…"
    }

    /// The newest words of a growing text, since the panel follows speech as it is finished.
    static func latest(of text: String, limit: Int = 60) -> String {
        let collapsed = WordTokens.words(text, .display).joined(separator: " ")
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
