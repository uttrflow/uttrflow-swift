import UttrflowCore

/// Cuts a field's value into the text either side of the selection, within the limits `InsertionPoint` keeps.
enum CaretText {
    /// The two sides of a caret, each already cut to what a prompt may carry.
    struct Sides: Equatable, Sendable {
        /// The text before the selection, ending at the caret.
        let preceding: String
        /// The text after the selection, starting at its end.
        let following: String
    }

    /// `selection` and `marked` are UTF-16 ranges; an input method's unconfirmed run is left out of both sides.
    static func around(_ value: String?, selection: Range<Int>?, marked: Range<Int>? = nil) -> Sides? {
        var selection = selection
        if let marked, !marked.isEmpty, let current = selection {
            let lower = min(current.lowerBound, marked.lowerBound)
            selection = lower..<max(current.upperBound, marked.upperBound)
        }
        guard let value, let ends = ends(of: selection, in: value) else { return nil }
        return Sides(
            preceding: suffix(value[..<ends.caret], limit: InsertionPoint.precedingLimit),
            following: prefix(value[ends.after...], limit: InsertionPoint.followingLimit))
    }

    /// A terminal screen's edges: the shell input before the caret and the rest of its row, never scrollback or a prompt.
    static func inTerminal(_ screen: String?, selection: Range<Int>?, windowTitle: String?) -> Sides? {
        guard let screen, let ends = ends(of: selection, in: screen),
            let typed = FocusedFieldSnapshot.shellInput(
                in: screen, before: ends.caret, windowTitle: windowTitle),
            !typed.isCut
        else { return nil }
        return Sides(
            preceding: suffix(Substring(typed.text), limit: InsertionPoint.precedingLimit),
            following: prefix(
                screen[ends.after...].prefix { !$0.isNewline }, limit: InsertionPoint.followingLimit))
    }

    /// The selection's two ends in `value`, out-of-range ends clamped.
    private static func ends(
        of selection: Range<Int>?, in value: String
    ) -> (caret: String.Index, after: String.Index)? {
        guard let selection else { return nil }
        let length = value.utf16.count
        let start = min(max(selection.lowerBound, 0), length)
        let end = min(max(selection.upperBound, start), length)
        return (String.Index(utf16Offset: start, in: value), String.Index(utf16Offset: end, in: value))
    }

    /// Moves a field-offset range into a read window by the distance the selection moved, or nil when either end is unknown.
    static func shift(_ range: Range<Int>?, from fieldCaret: Int?, to windowCaret: Int?) -> Range<Int>? {
        guard let range, let fieldCaret, let windowCaret else { return nil }
        let offset = fieldCaret - windowCaret
        return (range.lowerBound - offset)..<(range.upperBound - offset)
    }

    /// Keeps a UTF-16-bounded suffix without cutting a surrogate pair.
    private static func suffix(_ text: Substring, limit: Int) -> String {
        let units = text.utf16
        guard var start = units.index(units.endIndex, offsetBy: -limit, limitedBy: units.startIndex) else {
            return String(text)
        }
        if splitsSurrogatePair(units, at: start) { start = units.index(after: start) }
        return String(decoding: units[start..<units.endIndex], as: UTF16.self)
    }

    /// Keeps a UTF-16-bounded prefix without cutting a surrogate pair.
    private static func prefix(_ text: Substring, limit: Int) -> String {
        let units = text.utf16
        guard var end = units.index(units.startIndex, offsetBy: limit, limitedBy: units.endIndex) else {
            return String(text)
        }
        if splitsSurrogatePair(units, at: end) { end = units.index(before: end) }
        return String(decoding: units[units.startIndex..<end], as: UTF16.self)
    }

    /// Whether `index` falls between a UTF-16 high and low surrogate.
    private static func splitsSurrogatePair(_ units: Substring.UTF16View, at index: String.Index) -> Bool {
        guard index > units.startIndex, index < units.endIndex else { return false }
        let previous = units[units.index(before: index)]
        let next = units[index]
        return (0xD800...0xDBFF).contains(previous) && (0xDC00...0xDFFF).contains(next)
    }
}
