/// Reads a bounded stretch of a field's text by UTF-16 range, so a long document is never copied whole. See `Docs/insertion.md`.
public enum CaretWindow {
    /// UTF-16 units asked for per character wanted, room for surrogate pairs and combining marks.
    static let unitsPerCharacter = 4

    /// Units read past what is wanted, so a cut through a character lands in text that is thrown away.
    static let slack = 16

    /// How much of a field's start the mask-character check reads.
    public static let maskPrefixUnits = 64

    /// Text ending at `caret` whose last `characters` characters match the field's; `nil` means ask for the whole value.
    public static func before(
        _ caret: Int, characters: Int, ranged: (Range<Int>) -> String?
    ) -> String? {
        guard caret >= 0, characters >= 0 else { return nil }
        let start = max(0, caret - characters * unitsPerCharacter - slack)
        guard let text = ranged(start..<caret), text.utf16.count == caret - start else { return nil }
        if start == 0 { return text }
        let whole = text.dropFirst()  // the first character may be the back half of one the range cut
        guard whole.count > characters else { return nil }
        return String(whole)
    }

    /// Text starting at `end` whose first `characters` characters match the field's; `nil` means ask for the whole value.
    public static func after(
        _ end: Int, characters: Int, length: Int, ranged: (Range<Int>) -> String?
    ) -> String? {
        guard end >= 0, characters >= 0, end <= length else { return nil }
        let stop = min(length, end + characters * unitsPerCharacter + slack)
        guard let text = ranged(end..<stop), text.utf16.count == stop - end else { return nil }
        if stop == length { return text }
        let whole = text.dropLast()  // the last character may be the front half of one the range cut
        guard whole.count > characters else { return nil }
        return String(whole)
    }

    /// The field's first units, enough for the mask-character check; `nil` means ask for the whole value.
    public static func prefix(length: Int?, ranged: (Range<Int>) -> String?) -> String? {
        guard let length, length >= 0 else { return nil }
        let stop = min(length, maskPrefixUnits)
        guard let text = ranged(0..<stop), text.utf16.count == stop else { return nil }
        return text
    }
}
