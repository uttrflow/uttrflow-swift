// How much of a dictation is spoken back, after insertion or on request.
import UttrflowCore

/// How much of the words the after-insertion announcement speaks.
public enum DictationReadBack: String, Sendable, CaseIterable {
    /// The outcome alone, without the words.
    case off
    /// A glance at the words, the long-standing default.
    case preview
    /// Every word, exactly as it now stands in the field.
    case whole

    /// The words this setting speaks for `outcome`, or `nil` when it speaks none.
    func spoken(_ outcome: DictationOutcome) -> String? {
        switch self {
        case .off: nil
        case .preview: DictationPresenter.preview(of: DictationPresenter.said(outcome))
        case .whole: DictationPresenter.said(outcome)
        }
    }

    /// `text` in sentence-sized pieces that join back to `text` exactly; `nil` when empty or secure.
    public static func pieces(of text: String, intoSecureField: Bool) -> [String]? {
        guard let kept = KeptWords.of(text, intoSecureField: intoSecureField), !kept.isEmpty
        else { return nil }
        var pieces: [String] = []
        var current = ""
        var afterStop = false
        var afterStopAndSpace = false
        for character in kept {
            let isStop = character == "." || character == "!" || character == "?"
            // A piece ends before the first non-space after a stop and a space, so "3.5" stays whole.
            if afterStopAndSpace, !character.isWhitespace {
                pieces.append(current)
                current = ""
                afterStopAndSpace = false
            }
            if character.isWhitespace {
                afterStopAndSpace = afterStopAndSpace || afterStop
                afterStop = false
            } else {
                afterStop = isStop
            }
            current.append(character)
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
