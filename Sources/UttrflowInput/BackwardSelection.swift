/// Turns a count of characters before the caret into the UTF-16 range Accessibility selects, or the text it covers.
public enum BackwardSelection {
    /// The range covering `characters` before `caret`, or `nil` where the field's text cannot carry one.
    public static func range(
        in text: String, endingAt caret: Int, covering characters: Int
    ) -> Range<Int>? {
        guard let preceding = substring(in: text, endingAt: caret, covering: characters) else { return nil }
        let units = text.utf16
        return units.distance(from: units.startIndex, to: preceding.startIndex)..<caret
    }

    /// The `characters` before `caret` as whole characters, so an emoji is never cut into a lone surrogate.
    public static func text(
        in text: String, endingAt caret: Int, covering characters: Int
    ) -> String? {
        substring(in: text, endingAt: caret, covering: characters).map(String.init)
    }

    /// The characters before a UTF-16 caret, or `nil` when the caret splits a character or reaches past the start.
    private static func substring(
        in text: String, endingAt caret: Int, covering characters: Int
    ) -> Substring? {
        guard characters >= 0, caret >= 0 else { return nil }
        let units = text.utf16
        guard
            let caretIndex = units.index(units.startIndex, offsetBy: caret, limitedBy: units.endIndex),
            caretIndex.samePosition(in: text) != nil
        else { return nil }

        let head = text[..<caretIndex]
        guard head.count >= characters else { return nil }
        return head[head.index(head.endIndex, offsetBy: -characters)...]
    }
}
