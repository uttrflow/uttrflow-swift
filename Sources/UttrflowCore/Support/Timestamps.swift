import Foundation

/// The parts of a text that are only a time, or a date and a time, in the calendar's own words: a chat labels every message with one, and a model shown "…, 4 September at 6:41 PM" writes one after its own line.
public enum Timestamps {
    /// The text without its timestamp parts, which sit between commas in the labels chats publish.
    public static func without(_ text: String) -> String {
        text.split(separator: ", ", omittingEmptySubsequences: false)
            .filter { !isTimestamp($0) }
            .joined(separator: ", ")
    }

    /// Whether a part is a time, or a date with a month, weekday or day-half named in it — glued together or not, since some applications publish them without spaces.
    public static func isTimestamp(_ part: Substring) -> Bool {
        guard part.contains(where: \.isNumber) else { return false }
        var letters = ""
        for character in part.lowercased() where character.isLetter { letters.append(character) }
        // What is left once the digits and punctuation go must be calendar words end to end, longest first so a short name never hides a long one.
        var named = false
        while !letters.isEmpty {
            guard let word = words.first(where: { letters.hasPrefix($0) }) else { return false }
            if names.contains(word) { named = true }
            letters.removeFirst(word.count)
        }
        // "at 5" names no month and no day-half, so it is a message, not a stamp; "10:30" is a time even without a word.
        return named || hasTime(part)
    }

    /// Whether the part holds hours and minutes: a digit, a colon, two digits.
    static func hasTime(_ part: Substring) -> Bool {
        let characters = Array(part)
        for index in 1..<max(1, characters.count - 2)
        where characters[index] == ":" && characters[index - 1].isNumber && characters[index + 1].isNumber
            && characters[index + 2].isNumber
        {
            return true
        }
        return false
    }

    /// The month, weekday and day-half names of the current calendar, one of which a date names.
    static let names: Set<String> = {
        let calendar = Calendar.current
        let symbols =
            calendar.monthSymbols + calendar.shortMonthSymbols + calendar.standaloneMonthSymbols
            + calendar.weekdaySymbols + calendar.shortWeekdaySymbols + calendar.standaloneWeekdaySymbols
            + [calendar.amSymbol, calendar.pmSymbol]
        return Set(symbols.map { $0.lowercased().filter(\.isLetter) }.filter { !$0.isEmpty })
    }()

    /// The words a date is said with beside its names.
    static let connectives: Set<String> = ["at", "today", "yesterday"]

    /// Every word a stamp may be made of, longest first.
    static let words: [String] = names.union(connectives).sorted { $0.count > $1.count }
}
