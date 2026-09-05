/// A checklist inside a note, and the one operation that changes it.
///
/// E5 says a ticked box is content rather than decoration, which decides where this lives:
/// ticking one edits the clip and is written to disk like any other change. A checkbox
/// whose state lived in the view would be a tick that vanished the next time the panel
/// opened, and a checklist you cannot trust is worse than a bulleted list.
///
/// Deliberately narrow. This does not parse HTML in general — ``RichTextPlainForm`` does
/// that — it finds checkbox markers and flips one. Everything it does not recognise is
/// left exactly as it was, because a note is the user's writing and this is the only thing
/// in the app that edits one in place.
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
    ///
    /// Worth showing on a row: a checklist is the one kind of note whose *state* is the
    /// interesting part, and "2 of 5" says more from a one-line summary than the first
    /// line of it ever could.
    public static func progress(in html: String) -> (done: Int, total: Int)? {
        let found = marks(in: html)
        guard !found.isEmpty else { return nil }
        return (found.count { $0.isChecked }, found.count)
    }

    /// The same note with one box flipped, or `nil` when there is no such box.
    ///
    /// Rewrites the marker and nothing else — the surrounding note comes back byte for
    /// byte. `nil` rather than the unchanged note, so a caller can tell "there was nothing
    /// to tick" from "ticking it changed nothing", and never writes a no-op to disk.
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

    /// The three spellings that appear in real pasteboards.
    ///
    /// Apple Notes marks the `<li>`; GitHub writes a real `<input type="checkbox">`;
    /// TipTap and ProseMirror use `data-checked`. All three are matched on whole
    /// attribute tokens rather than by substring, because `unchecked` contains `checked`
    /// and a substring test ticks every empty box in the note.
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
        // Bounded by the quote or a space on each side, so `unchecked` is never hit while
        // looking for `checked`.
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
    /// The note form of some plain text.
    ///
    /// Line breaks become paragraphs and nothing else is interpreted. Deliberately not
    /// Markdown: a clip containing `# 3 things` is a note about three things, not a
    /// heading, and guessing wrong rewrites the user's words the moment they promote it.
    /// Formatting is something they apply afterwards, deliberately, in the editor.
    ///
    /// The plain form is untouched by this — ``Clip/text`` stays exactly what was copied —
    /// so E6's "the original plain text stays recoverable" is not a feature that has to be
    /// built, it is a consequence of never deriving one from the other.
    public static func note(from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<p>" + escaped(String($0)) + "</p>" }
            .joined()
    }

    /// The five characters that would otherwise turn the user's own words into markup the
    /// next time this note is read back.
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
