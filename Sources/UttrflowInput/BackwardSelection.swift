/// Turns a count of characters before the caret into the UTF-16 range Accessibility selects.
public enum BackwardSelection {
    /// The range covering `characters` before `caret`, or `nil` where the field's text cannot carry one.
    public static func range(
        in text: String, endingAt caret: Int, covering characters: Int
    ) -> Range<Int>? {
        guard characters >= 0, caret >= 0 else { return nil }
        let units = text.utf16
        guard
            let caretIndex = units.index(units.startIndex, offsetBy: caret, limitedBy: units.endIndex),
            caretIndex.samePosition(in: text) != nil
        else { return nil }

        let head = text[..<caretIndex]
        guard head.count >= characters else { return nil }
        let start = head.index(head.endIndex, offsetBy: -characters)
        return units.distance(from: units.startIndex, to: start)..<caret
    }
}
