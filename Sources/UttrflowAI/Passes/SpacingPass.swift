public import UttrflowCore

/// Fixes a mark that arrived as its own word onto the word before it, and collapses doubled clause marks.
public struct SpacingPass: CleaningPass {
    public static let id: PassID = "spacing"

    static let clauseMarks: Set<Character> = [",", ".", "?", "!", ":", ";"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var previous: Int?
        for index in draft.presentIndices {
            let text = draft.words[index].text
            if let previous, text.allSatisfy(Self.clauseMarks.contains) {
                draft.replace(at: previous, with: draft.words[previous].text + text, by: Self.id)
                draft.remove(at: index, by: Self.id)
                continue
            }
            draft.replace(at: index, with: Self.collapsed(text), by: Self.id)
            previous = index
        }
        return draft
    }

    /// The word with a run of the same comma, colon or semicolon at its end reduced to one.
    private static func collapsed(_ text: String) -> String {
        guard let last = text.last, ",;:".contains(last) else { return text }
        var trimmed = text
        while trimmed.count > 1, trimmed.dropLast().last == last { trimmed.removeLast() }
        return trimmed
    }
}
