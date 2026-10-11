public import UttrflowCore

/// The key an application may take the next word of a suggestion with; no application has one until the user chooses it.
public enum WordAcceptKey: String, Sendable, Equatable, CaseIterable, Codable {
    /// ⌥→, which moves by word in most editors, so it is only ever armed where the user asked for it.
    case optionRightArrow
    /// ⌘→, which moves to the end of the line in most editors, so it is only ever armed where the user asked for it.
    case commandRightArrow

    /// The keystroke that presses it.
    public var stroke: KeyStroke {
        switch self {
        case .optionRightArrow: KeyStroke(.rightArrow, modifiers: .option)
        case .commandRightArrow: KeyStroke(.rightArrow, modifiers: .command)
        }
    }
}

/// How much of a suggestion one press of the word key takes. See `Docs/predict-accept.md`.
public enum WordAcceptance {
    /// The line the field holds once the next word of `line` is taken after `typed`, or nil when taking a word is not a smaller step than taking the whole line.
    public static func next(of line: String, after typed: String) -> String? {
        guard let edit = Acceptance.edit(accepting: line, after: typed), !edit.isReplacement else {
            return nil
        }
        var piece = ""
        var inWord = false
        for character in edit.inserted {
            if character.isWhitespace {
                if inWord { break }
            } else {
                inWord = true
            }
            piece.append(character)
        }
        guard inWord, piece.count < edit.inserted.count else { return nil }
        return typed + piece
    }
}
