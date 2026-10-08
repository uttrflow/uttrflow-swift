/// Checklist boxes in a note.
public enum NoteChecklist {
    /// One box, and whether it is ticked.
    public struct Item: Sendable, Equatable {
        public let isChecked: Bool

        public init(isChecked: Bool) {
            self.isChecked = isChecked
        }
    }

    /// The boxes in a note, in the order its plain form writes them.
    public static func items(in html: String) -> [Item] {
        RichTextPlainForm.checkboxes(inHTML: html).map(Item.init(isChecked:))
    }

    /// How much of a checklist is done, or `nil` when the note has no boxes.
    public static func progress(in html: String) -> (done: Int, total: Int)? {
        let boxes = RichTextPlainForm.checkboxes(inHTML: html)
        guard !boxes.isEmpty else { return nil }
        return (boxes.count { $0 }, boxes.count)
    }
}

/// E6 — turning a plain clip into a note.
public enum NotePromotion {
    /// The note form of some plain text: line breaks become paragraphs, and nothing else is interpreted.
    public static func note(from text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "<p>" + escaped(String($0)) + "</p>" }
            .joined()
    }

    /// The five characters that would otherwise become markup when the note is read back.
    static func escaped(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }
}
