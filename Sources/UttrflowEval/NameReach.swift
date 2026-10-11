// Measures how far before the caret a dictated name last appears, to size the read behind a name vocabulary.

/// Recall of dictated names against the size of the window of text before the caret.
struct NameReach {
    /// One session: the text before the caret and the names the person then dictates.
    struct Session: Equatable {
        let before: String
        let dictated: [String]
    }

    /// The window sizes in UTF-16 units that the table compares.
    static let windows = [300, 1000, 4000]

    /// Units from the start of the nearest whole-token `name` to the caret, or nil when it never appears.
    static func distance(of name: String, in before: String) -> Int? {
        let text = Array(before.utf16)
        let target = Array(name.utf16)
        guard !target.isEmpty, text.count >= target.count else { return nil }
        var start = text.count - target.count
        while start >= 0 {
            if Array(text[start..<(start + target.count)]) == target,
                isBoundary(text, before: start), isBoundary(text, before: start + target.count)
            {
                return text.count - start
            }
            start -= 1
        }
        return nil
    }

    /// The share of dictated names whose nearest occurrence lies wholly inside `window` units; nil when none are dictated.
    static func recall(_ sessions: [Session], window: Int) -> Double? {
        let names = sessions.flatMap { session in session.dictated.map { (session.before, $0) } }
        guard !names.isEmpty else { return nil }
        let found = names.filter { text, name in
            distance(of: name, in: text).map { $0 <= window } ?? false
        }
        return Double(found.count) / Double(names.count)
    }

    /// Whether the gap before `index` separates two tokens: either edge of the text, or an identifier unit beside a non-identifier one.
    private static func isBoundary(_ text: [UInt16], before index: Int) -> Bool {
        guard index > 0, index < text.count else { return true }
        return isIdentifier(text[index - 1]) != isIdentifier(text[index])
    }

    /// Letters, digits and underscore in ASCII; any other unit separates tokens.
    private static func isIdentifier(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
            || unit == 0x5F
    }
}
