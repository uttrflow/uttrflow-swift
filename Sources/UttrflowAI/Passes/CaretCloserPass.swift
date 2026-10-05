public import UttrflowCore

/// Removes closing delimiters the model inferred from an opener before the caret, not from the dictation.
public struct CaretCloserPass: PieceCleaningPass {
    public static let id: PassID = "caretCloser"

    public let precedingText: String?
    /// The piece after its ordinary cleaning passes, before the model rewrites it.
    public let spokenText: String?

    public init(precedingText: String? = nil, spokenText: String? = nil) {
        self.precedingText = precedingText
        self.spokenText = spokenText
    }

    public func apply(_ draft: Draft) -> Draft {
        guard let precedingText, CaretStructure(precedingText: precedingText).hasOpenDelimiter,
            let index = draft.presentIndices.last(where: { !draft.words[$0].isLayoutMark })
        else { return draft }

        let spokenClosers = Self.closers(atEndOf: spokenText ?? "")
        var remainingSpokenClosers = spokenClosers
        let original = draft.words[index].text
        let shape = WordShape(original)
        let delimiterRun = shape.core.isEmpty ? shape.prefix + shape.suffix : shape.suffix
        var suffix = ""
        for character in delimiterRun {
            guard Self.closingDelimiters.contains(character) else {
                suffix.append(character)
                continue
            }
            if let count = remainingSpokenClosers[character], count > 0 {
                if count == 1 {
                    remainingSpokenClosers.removeValue(forKey: character)
                } else {
                    remainingSpokenClosers[character] = count - 1
                }
                suffix.append(character)
            }
        }
        guard suffix != delimiterRun else { return draft }

        var draft = draft
        let replacement = shape.core.isEmpty ? suffix : shape.prefix + shape.core + suffix
        if replacement.isEmpty {
            draft.remove(at: index, by: Self.id)
        } else {
            draft.replace(at: index, with: replacement, by: Self.id)
        }
        return draft
    }

    /// Counts closing delimiters carried by the last spoken token, so a dictated close is never removed.
    private static func closers(atEndOf text: String) -> [Character: Int] {
        guard let last = text.split(whereSeparator: \.isWhitespace).last else { return [:] }
        let shape = WordShape(String(last))
        let delimiterRun = shape.core.isEmpty ? shape.prefix + shape.suffix : shape.suffix
        return delimiterRun.reduce(into: [:]) { counts, character in
            guard closingDelimiters.contains(character) else { return }
            counts[character, default: 0] += 1
        }
    }

    private static let closingDelimiters: Set<Character> = [
        ")", "]", "}", "\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}",
    ]
}
