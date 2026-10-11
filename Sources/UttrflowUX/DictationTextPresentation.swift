import Foundation
import UttrflowClipboard
public import UttrflowCore

/// A dictation's display form and clipboard handling decision, using the clipboard's secret rules.
public struct DictationTextPresentation: Sendable, Equatable {
    /// The words retained for copying or inserting.
    public let text: String
    /// Whether the text is a credential that must be hidden and written as concealed.
    public let isSecret: Bool

    /// Detects secrets once, by shape or by holding the text of a snippet marked secret (`secretPhrases`).
    public init(_ text: String, secretPhrases: [String] = []) {
        self.text = text
        isSecret =
            ClipKindDetector.kind(of: text) == .secret
            || secretPhrases.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// The text a dictation surface may show.
    public var displayText: String { isSecret ? PanelPresenter.mask : text }
}

extension Sequence where Element == Snippet {
    /// The text each secret snippet writes, trimmed, for ``DictationTextPresentation``.
    public var secretPhrases: [String] {
        filter(\.isSecret)
            .map { $0.body.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
