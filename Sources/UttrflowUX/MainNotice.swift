// What the main window says when a change it was asked to make was refused.
public import UttrflowCore

/// A refused change, said where the user pressed; the window carries the latest one only.
public struct MainNotice: Sendable, Equatable {
    /// The failure's own sentence, so the page and the log cannot word one refusal two ways.
    public let message: String
    /// The SF Symbol beside the sentence.
    public let symbolName: String
    /// How it is tinted.
    public let tone: MainTone
    /// The one thing offered besides putting the notice away, when there is something to do.
    public let action: MainAction?

    /// Builds a notice from its parts.
    public init(message: String, symbolName: String, tone: MainTone, action: MainAction? = nil) {
        self.message = message
        self.symbolName = symbolName
        self.tone = tone
        self.action = action
    }

    /// The first sentence, drawn in bold as the notice's title.
    public var headline: String { FailurePresenter.splitIntoSentences(message).headline }

    /// Whatever follows the first sentence, drawn under the title; absent when there was only one.
    public var detail: String? { FailurePresenter.splitIntoSentences(message).detail }
}

extension MainNotice {
    /// What an error nobody foresaw says, so a type name never reaches the screen.
    public static let unforeseenMessage = "Something went wrong. Please try again."

    /// The system clipboard refused the requested contents.
    public static let clipboardCopyFailed = MainNotice(
        message: "Could not copy to the clipboard. Please try again.",
        symbolName: "exclamationmark.triangle", tone: .warning)

    /// Explains a first rules-only dictation caused by Apple Intelligence readiness.
    public static func appleIntelligenceUnavailable(_ reason: TransformerUnavailableReason) -> MainNotice {
        let message: String
        let action: MainAction?
        switch reason {
        case .appleIntelligenceDisabled:
            message = "Apple Intelligence is switched off. Uttrflow used built-in rules for this dictation."
            action = MainAction(
                title: MainPresenter.title(for: .openSystemSettings(.appleIntelligence)),
                intent: .recover(.openSystemSettings(.appleIntelligence)))
        case .modelNotReady:
            message =
                "Apple Intelligence is downloading its model. Uttrflow used built-in rules for this dictation."
            action = nil
        case .deviceNotEligible:
            message =
                "This Mac cannot run Apple Intelligence. Uttrflow used built-in rules for this dictation."
            action = nil
        case .other(let detail):
            message =
                "Apple Intelligence is unavailable (\(detail)). Uttrflow used built-in rules for this dictation."
            action = nil
        }
        let drawing = Self.drawing(for: .degraded)
        return MainNotice(
            message: message, symbolName: drawing.symbolName, tone: drawing.tone, action: action)
    }

    /// Says that the last dictation went in as heard because no clean-up finished, or nil when one did.
    public static func cleanUpSkipped(by cleanedBy: TransformerKind) -> MainNotice? {
        guard cleanedBy == .untidied else { return nil }
        let drawing = Self.drawing(for: .degraded)
        return MainNotice(
            message:
                "Inserted without clean-up. Tidying did not finish, so your words went in exactly as heard.",
            symbolName: drawing.symbolName, tone: drawing.tone)
    }

    /// The notice for a refused change, from the failure's own sentence and what it cost the user.
    public init(refusing error: any Error) {
        let failure = error as? any UttrflowFailure
        // Recoverable rather than a fault, as ``DictationFailure`` reads an unforeseen error.
        let drawing = Self.drawing(for: failure?.severity ?? .recoverable)
        self.init(
            message: failure?.userMessage ?? Self.unforeseenMessage,
            symbolName: drawing.symbolName,
            tone: drawing.tone,
            action: Self.action(for: failure?.recovery))
    }

    /// How loudly a refusal is drawn, from what it cost the user alone.
    static func drawing(for severity: FailureSeverity) -> (symbolName: String, tone: MainTone) {
        switch severity {
        case .blocking, .degraded: ("exclamationmark.triangle", .critical)
        case .recoverable: ("arrow.clockwise", .warning)
        case .informational: ("info.circle", .neutral)
        }
    }

    /// The button a recovery earns; a recovery that only dismisses earns none, as the notice already closes.
    static func action(for recovery: RecoveryAction?) -> MainAction? {
        guard let recovery, recovery != .pasteManually else { return nil }
        return MainAction(title: MainPresenter.title(for: recovery), intent: .recover(recovery))
    }
}
