// Turns any failure into what the user sees: headline, detail, badge, severity, placement, and action.
public import UttrflowCore

/// Which surface carries the notice.
public enum FailurePlacement: Sendable, Equatable, CaseIterable {
    /// Stays until the cause is gone; the menu bar is the only always-visible surface.
    case menuBar
    /// Shown beside the work and allowed to dismiss itself.
    case floatingButton
}

/// The one thing offered to the user, and the words on it.
public struct FailureAction: Sendable, Equatable {
    /// The words on the button.
    public let title: String
    /// What pressing it does.
    public let recovery: RecoveryAction

    /// Builds an action.
    public init(title: String, recovery: RecoveryAction) {
        self.title = title
        self.recovery = recovery
    }
}

/// Everything the interface needs in order to show one failure.
public struct FailurePresentation: Sendable, Equatable {
    /// The first sentence of the failure's own message: what went wrong.
    public let headline: String
    /// Whatever the message said after the first sentence; absent when there was only one.
    public let detail: String?
    /// SF Symbol for the badge beside the message.
    public let symbolName: String
    /// How much the failure costs the user.
    public let severity: FailureSeverity
    /// Which surface carries it.
    public let placement: FailurePlacement
    /// Absent when nothing the user could do would help.
    public let action: FailureAction?

    /// Builds a presentation from its parts.
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

/// Turns any ``UttrflowFailure`` into what the user sees, from its message, recovery and severity alone.
public enum FailurePresenter {
    /// Presents a failure from its own message, recovery and severity.
    public static func present(_ failure: some UttrflowFailure) -> FailurePresentation {
        present(
            message: failure.userMessage, recovery: failure.recovery, severity: failure.severity)
    }

    /// The same for a failure already reduced to a sentence, an action and a cost; both share one body.
    public static func present(
        message: String, recovery: RecoveryAction?, severity: FailureSeverity
    ) -> FailurePresentation {
        let (headline, detail) = splitIntoSentences(message)
        return FailurePresentation(
            headline: headline,
            detail: detail,
            symbolName: symbolName(for: recovery),
            severity: severity,
            // A blocking failure has to outlive the moment it happened in; everything else is news.
            placement: severity == .blocking ? .menuBar : .floatingButton,
            action: recovery.map { FailureAction(title: title(for: $0), recovery: $0) }
        )
    }

    /// Splits a message at the first sentence break into the headline and the line that explains it.
    static func splitIntoSentences(_ message: String) -> (headline: String, detail: String?) {
        guard let split = message.firstRange(of: ". ") else { return (message, nil) }
        let detail = String(message[split.upperBound...])
        // A message ending in ". " would leave an empty second line, which reads as a rendering fault.
        return (String(message[..<split.lowerBound]) + ".", detail.isEmpty ? nil : detail)
    }

    /// The badge beside the message, naming the thing that needs attention rather than the failure.
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
        case .retryFromRecording: "arrow.clockwise"
        }
    }

    /// The words on the one button: a verb and its object, never "OK".
    static func title(for recovery: RecoveryAction) -> String {
        switch recovery {
        case .openSystemSettings: "Open System Settings"
        case .retry: "Try Again"
        case .downloadSpeechModel: "Finish Setup"
        case .pasteManually: "Paste"
        case .showRecentDictations: "Show Recent"
        case .retryFromRecording: "Retry"
        }
    }
}
