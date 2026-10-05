// Plans the Markdown structure rows of the spoken-command registry against the selection. See `Docs/commands.md`.
public import UttrflowCore

/// Reads and applies the `lineMark` and `spanMark` rows, only where the document renders Markdown.
public enum MarkdownCommand {
    /// The text that replaces the selection, or `nil` when the words are no Markdown row or the edit cannot apply here.
    public static func edit(for utterance: String, on target: AppContext) -> String? {
        guard CaretStructure.isMarkdown(documentName: target.documentName),
            let row = row(for: utterance)
        else { return nil }
        let selection = target.selectedText ?? ""
        let atLineStart = (target.precedingText ?? "").last.map(\.isNewline) ?? true
        switch row.action {
        case .lineMark:
            guard atLineStart else { return nil }
            return markLines(selection, with: row.text)
        case .spanMark:
            return wrap(selection, in: row.text, atLineStart: atLineStart)
        default:
            return nil
        }
    }

    /// The Markdown row the whole utterance names, ignoring the recogniser's case and closing mark.
    static func row(for utterance: String) -> SpokenCommand? {
        let keys = utterance.split(whereSeparator: \.isWhitespace).map { WordShape(String($0)).key }
        return SpokenCommands.markdown.first { $0.words == keys }
    }

    /// The mark before every non-empty line; with nothing selected, the mark alone at the caret.
    private static func markLines(_ selection: String, with mark: String) -> String {
        guard !selection.isEmpty else { return mark }
        return selection.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? String($0) : mark + $0 }
            .joined(separator: "\n")
    }

    /// The selection between the mark and the mark read backwards, so the span closes where the selection ends.
    private static func wrap(_ selection: String, in mark: String, atLineStart: Bool) -> String? {
        let isBlock = mark.contains(where: \.isNewline)
        let leading = selection.prefix { isBlock ? $0.isNewline : $0.isWhitespace }
        let trailing = String(selection.reversed().prefix { $0.isWhitespace }.reversed())
        let body = selection.dropFirst(leading.count).dropLast(trailing.count)
        guard !body.isEmpty, !isBlock || atLineStart || !leading.isEmpty else { return nil }
        return leading + mark + body + String(mark.reversed()) + trailing
    }
}
