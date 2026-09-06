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

    /// `selection` is in UTF-16 units, as Accessibility reports it; out-of-range ends are clamped.
    static func around(_ value: String?, selection: Range<Int>?) -> Sides? {
        guard let value, let selection else { return nil }
        let length = value.utf16.count
        let start = min(max(selection.lowerBound, 0), length)
        let end = min(max(selection.upperBound, start), length)
        let caret = String.Index(utf16Offset: start, in: value)
        let after = String.Index(utf16Offset: end, in: value)
        return Sides(
            preceding: String(value[..<caret].suffix(InsertionPoint.precedingLimit)),
            following: String(value[after...].prefix(InsertionPoint.followingLimit)))
    }
}
