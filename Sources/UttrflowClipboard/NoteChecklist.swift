/// A checklist inside a note and the one operation that changes it; everything unrecognised is left as is.
public enum NoteChecklist {
    /// One box, and whether it is ticked.
    public struct Item: Sendable, Equatable {
        public let isChecked: Bool

        public init(isChecked: Bool) {
            self.isChecked = isChecked
        }
    }

    /// The boxes in a note, in the order they are written.
    public static func items(in html: String) -> [Item] {
        marks(in: html).map { Item(isChecked: $0.isChecked) }
    }

    /// How much of a checklist is done, or `nil` when the note has no boxes.
    public static func progress(in html: String) -> (done: Int, total: Int)? {
        let found = marks(in: html)
        guard !found.isEmpty else { return nil }
        return (found.count { $0.isChecked }, found.count)
    }

    /// The same note with one box flipped and nothing else changed, or `nil` when there is no such box.
    public static func toggling(_ index: Int, in html: String) -> String? {
        let found = marks(in: html)
        guard index >= 0, index < found.count else { return nil }
        let mark = found[index]
        var edited = html
        edited.replaceSubrange(mark.range, with: mark.flipped)
        return edited
    }

    // MARK: - Finding the boxes

    /// Where a box is written, and what it would be written as if flipped.
    private struct Mark {
        let range: Range<String.Index>
        let isChecked: Bool
        let flipped: String
    }

    /// The three spellings real pasteboards use, matched on whole tokens, as `unchecked` contains `checked`.
    private static func marks(in html: String) -> [Mark] {
        var found: [Mark] = []
        var index = html.startIndex

        while let open = html[index...].firstIndex(of: "<") {
            guard let close = html[open...].firstIndex(of: ">") else { break }
            index = html.index(after: close)
            if let mark = mark(of: String(html[open...close]), at: open..<index) {
                found.append(mark)
            }
        }
        return found
    }

    /// The box this tag is, or `nil` when it is not one.
    private static func mark(of tag: String, at range: Range<String.Index>) -> Mark? {
        let lower = tag.lowercased()
        let box = lower.hasPrefix("<input") ? inputBox(tag, lower) : listItemBox(tag, lower)
        return box.map { Mark(range: range, isChecked: $0.isChecked, flipped: $0.flipped) }
    }

    /// A real `<input type="checkbox">`, as GitHub writes one.
    private static func inputBox(_ tag: String, _ lower: String) -> (isChecked: Bool, flipped: String)? {
        guard
            lower.contains("type=\"checkbox\"") || lower.contains("type='checkbox'")
                || lower.contains("type=checkbox")
        else { return nil }
        // A bare `checked` is the HTML spelling; `checked="checked"` is the XHTML one.
        let isChecked = lower.contains(" checked") || lower.contains("checked=")
        let flipped =
            isChecked
            ? withoutCheckedAttribute(tag)
            : tag.replacingOccurrences(of: ">", with: " checked>", options: .backwards)
        return (isChecked, flipped)
    }

    /// Apple Notes and TipTap mark the item rather than writing an input.
    private static func listItemBox(_ tag: String, _ lower: String) -> (isChecked: Bool, flipped: String)? {
        guard lower.hasPrefix("<li") else { return nil }
        let classes = tokens(of: "class", in: lower)
        let isChecked = classes.contains("checked") || lower.contains("data-checked=\"true\"")

        if classes.contains("checked") {
            return (isChecked, replacingToken("checked", with: "unchecked", in: tag))
        }
        if classes.contains("unchecked") {
            return (isChecked, replacingToken("unchecked", with: "checked", in: tag))
        }
        if lower.contains("data-checked=\"true\"") {
            return (isChecked, swappingDataChecked(tag, from: "true", to: "false"))
        }
        if lower.contains("data-checked=\"false\"") {
            return (isChecked, swappingDataChecked(tag, from: "false", to: "true"))
        }
        return nil
    }

    private static func swappingDataChecked(_ tag: String, from old: String, to new: String) -> String {
        tag.replacingOccurrences(of: "data-checked=\"\(old)\"", with: "data-checked=\"\(new)\"")
    }

    /// The values of one attribute, split into whole words.
    private static func tokens(of attribute: String, in lower: String) -> [String] {
        guard let start = lower.range(of: "\(attribute)=\"") else { return [] }
        let rest = lower[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return [] }
        return rest[..<end].split(separator: " ").map(String.init)
    }

    private static func replacingToken(
        _ token: String, with replacement: String, in tag: String
    )
        -> String
    {
        // Bounded by a quote or a space on each side, so `unchecked` is never hit.
        for boundary in ["\"\(token)\"", "\"\(token) ", " \(token)\"", " \(token) "] {
            if let found = tag.range(of: boundary, options: .caseInsensitive) {
                let swapped = boundary.replacingOccurrences(of: token, with: replacement)
                return tag.replacingCharacters(in: found, with: swapped)
            }
        }
        return tag
    }

    private static func withoutCheckedAttribute(_ tag: String) -> String {
        var edited = tag
        for spelling in [" checked=\"checked\"", " checked='checked'", " checked=\"\"", " checked"] {
            if let found = edited.range(of: spelling, options: .caseInsensitive) {
                edited.removeSubrange(found)
                return edited
            }
        }
        return edited
    }
}

/// E6 — turning a plain clip into a note.
public enum NotePromotion {
    /// The note form of some plain text: line breaks become paragraphs, and nothing else is interpreted.
    public static func note(from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
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
