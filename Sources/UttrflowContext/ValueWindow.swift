public import struct Foundation.NSRange

/// The stretch of a long field's value a turn reads, around the caret, instead of the whole value.
public enum ValueWindow {
    /// How many characters before the caret the line and its preceding context can use.
    static let contextCharacters = FocusedFieldSnapshot.lineReadLimit + 400 + 1

    /// UTF-16 units read before the caret, wide enough that a character of up to four units still fits the context.
    public static let unitsBefore = contextCharacters * 4

    /// UTF-16 units read after the caret, which is where the end of its line is looked for.
    public static let unitsAfter = 1024

    /// UTF-16 units of a selection retained around its start.
    public static let selectionLimit = 1024

    /// The range to ask for, or `nil` when the whole value is no longer than the window and is read whole.
    public static func range(count: Int, selection: NSRange, need: ContextNeed = .turn) -> NSRange? {
        guard count > need.unitsBefore + need.unitsAfter, selection.location >= 0, selection.length >= 0,
            selection.location <= count
        else { return nil }
        let caret = selection.location
        let start = max(0, caret - need.unitsBefore)
        let selectedLength = min(selection.length, need.selectionUnits)
        let end = min(count, caret + min(selectedLength + need.unitsAfter, count - caret))
        return NSRange(location: start, length: max(0, end - start))
    }

    /// The value and selection a turn works from, never fetching a long or unknown value whole.
    public static func read(
        count: Int?, selection: NSRange?, need: ContextNeed = .turn, whole: () -> String?,
        part: (NSRange) -> String?
    ) -> (value: String?, selection: NSRange?) {
        guard let count else { return (nil, selection) }
        guard count > need.unitsBefore + need.unitsAfter else { return (whole(), selection) }
        guard let selection, let window = range(count: count, selection: selection, need: need) else {
            return (nil, selection)
        }
        guard let text = part(window), text.utf16.count == window.length else { return (nil, selection) }
        let shifted = NSRange(
            location: selection.location - window.location, length: min(selection.length, need.selectionUnits)
        )
        return (text, shifted)
    }
}
