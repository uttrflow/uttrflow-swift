public import UttrflowCore

/// Which surface carries the notice.
public enum FailurePlacement: Sendable, Equatable, CaseIterable {
    /// Stays until the cause is gone. The menu bar is the only always-visible surface,
    /// so anything that must be fixed before dictating again belongs there — a notice
    /// that dismisses itself would leave the user pressing a shortcut that cannot work.
    case menuBar
    /// Shown beside the work and allowed to dismiss itself.
    case floatingButton
}

/// The one thing offered to the user, and the words on it.
public struct FailureAction: Sendable, Equatable {
    public let title: String
    public let recovery: RecoveryAction

    public init(title: String, recovery: RecoveryAction) {
        self.title = title
        self.recovery = recovery
    }
}

/// Everything the interface needs in order to show one failure.
public struct FailurePresentation: Sendable, Equatable {
    /// The first sentence of the failure's own message: what went wrong.
    public let headline: String
    /// Whatever the message said after that — usually what it means for the user.
    /// Absent when the failure only had one sentence to offer.
    public let detail: String?
    /// SF Symbol for the badge beside the message.
    public let symbolName: String
    public let severity: FailureSeverity
    public let placement: FailurePlacement
    /// Absent when nothing the user could do would help.
    public let action: FailureAction?

    public init(
        headline: String, detail: String?, symbolName: String, severity: FailureSeverity,
        placement: FailurePlacement, action: FailureAction?
    ) {
        self.headline = headline
        self.detail = detail
        self.symbolName = symbolName
        self.severity = severity
        self.placement = placement
        self.action = action
    }
}

/// Turns any ``UttrflowFailure`` into what the user sees.
///
/// Everything below is decided from ``UttrflowFailure/userMessage``,
/// ``UttrflowFailure/recovery`` and ``UttrflowFailure/severity`` and from nothing else.
/// There is deliberately no switch over error types here: a new error that conforms to
/// the protocol arrives with a user-facing story already written, and one that does not
/// is a hole in the error rather than a hole in this file. A test walks every error in
/// the product through it, which is what keeps that true.
///
/// Severity used to be inferred here from the recovery action, which is the same
/// mistake in a subtler form — it guessed at something only the error knows, and read
/// ``HotkeyError/observationNotPermitted`` as degraded when a shortcut that never fires
/// leaves no way to dictate at all. What is left here is the one judgement that
/// genuinely belongs to the interface: where a notice of a given severity is put.
public enum FailurePresenter {
    public static func present(_ failure: some UttrflowFailure) -> FailurePresentation {
        present(
            message: failure.userMessage, recovery: failure.recovery, severity: failure.severity)
    }

    /// The same, for a failure the pipeline has already reduced to a sentence, an action
    /// and a cost.
    ///
    /// The pipeline's stages are generic over the type they throw, so what reaches the
    /// interface is the three things the protocol promised rather than the error itself.
    /// Both entry points share one body, so the two can never present the same failure
    /// differently.
    public static func present(
        message: String, recovery: RecoveryAction?, severity: FailureSeverity
    ) -> FailurePresentation {
        let (headline, detail) = splitIntoSentences(message)
        return FailurePresentation(
            headline: headline,
            detail: detail,
            symbolName: symbolName(for: recovery),
            severity: severity,
            // A blocking failure has to outlive the moment it happened in; everything
            // else is news about a dictation that is already over.
            placement: severity == .blocking ? .menuBar : .floatingButton,
            action: recovery.map { FailureAction(title: title(for: $0), recovery: $0) }
        )
    }

    /// Splits a message into the line the user reads first and the line that explains it.
    ///
    /// The protocol asks for plain language, and plain language about a failure is
    /// almost always "here is what happened" followed by "here is what that means".
    /// Splitting on the sentence break gets the design's two-line banner out of one
    /// string, and a single-sentence message degrades to a headline with nothing under
    /// it rather than to a headline that has been guessed at.
    static func splitIntoSentences(_ message: String) -> (headline: String, detail: String?) {
        guard let split = message.firstRange(of: ". ") else { return (message, nil) }
        let detail = String(message[split.upperBound...])
        // A message ending in ". " would leave an empty second line, which reads as a
        // rendering fault rather than as a message with nothing more to say.
        return (String(message[..<split.lowerBound]) + ".", detail.isEmpty ? nil : detail)
    }

    /// The badge beside the message. Names the thing that needs attention rather than
    /// the failure, so the user knows where they are being sent before reading a word.
    static func symbolName(for recovery: RecoveryAction?) -> String {
        guard let recovery else { return "exclamationmark.triangle" }
        return switch recovery {
        case .openSystemSettings(.microphone): "mic.slash"
        case .openSystemSettings(.accessibility): "accessibility"
        case .openSystemSettings(.appleIntelligence): "sparkles"
        case .downloadSpeechModel: "arrow.down.circle"
        case .retry: "arrow.clockwise"
        case .pasteManually: "doc.on.clipboard"
        case .showRecentDictations: "menubar.arrow.up.rectangle"
        }
    }

    /// The words on the one button. A verb and its object, never "OK": the button is
    /// the fix, so it should say what it will do.
    static func title(for recovery: RecoveryAction) -> String {
        switch recovery {
        case .openSystemSettings: "Open System Settings"
        case .retry: "Try Again"
        case .downloadSpeechModel: "Finish Setup"
        case .pasteManually: "Paste"
        case .showRecentDictations: "Show Recent"
        }
    }
}
