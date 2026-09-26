public import struct Foundation.NSRange

/// The stretch of a long field's value a turn reads, around the caret, instead of the whole value.
public enum ValueWindow {
    /// How many characters before the caret the line and its preceding context can use.
    static let contextCharacters = FocusedFieldSnapshot.lineReadLimit + 400 + 1

    /// UTF-16 units read before the caret, wide enough that a character of up to four units still fits the context.
    public static let unitsBefore = contextCharacters * 4

    /// UTF-16 units read after the caret, which is where the end of its line is looked for.
    public static let unitsAfter = 1024

    /// The range to ask for, or `nil` when the whole value is no longer than the window and is read whole.
    public static func range(count: Int, selection: NSRange) -> NSRange? {
        guard count > unitsBefore + unitsAfter, selection.location >= 0, selection.length >= 0 else {
            return nil
        }
        let caret = min(selection.location, count)
        let start = max(0, caret - unitsBefore)
        let end = min(count, caret + selection.length + unitsAfter)
        return NSRange(location: start, length: max(0, end - start))
    }

    /// The value and selection a turn works from, fetching only the window where the field can answer for a range.
    public static func read(
        count: Int?, selection: NSRange?, whole: () -> String?, part: (NSRange) -> String?
    ) -> (value: String?, selection: NSRange?) {
        guard let count, let selection, let window = range(count: count, selection: selection),
            let text = part(window), text.utf16.count == window.length
        else { return (whole(), selection) }
        let shifted = NSRange(location: selection.location - window.location, length: selection.length)
        return (text, shifted)
    }
}
