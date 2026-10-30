// What the main window says when a change it was asked to make was refused.
import Foundation
import UttrflowCore

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

extension MainNotice {
    /// Offers to run a fixed dictation's kept audio again, which copies the new words.
    package static func retryAfterFix(saving word: String, recording: UUID) -> MainNotice {
        MainNotice(
            message: "Saved “\(word)”. Retry the recording to see the fix; the new words are copied.",
            symbolName: "character.book.closed.fill", tone: .neutral,
            action: MainAction(
                title: "Retry This Recording", symbolName: "arrow.clockwise", intent: .retryRecording(recording)))
    }
}
