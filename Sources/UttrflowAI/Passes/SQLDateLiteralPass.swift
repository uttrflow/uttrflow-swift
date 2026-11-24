import Foundation
import UttrflowCore

extension PassID {
    /// A date written after a comparison word in a query, as the one quoted literal the statement reads.
    static let sqlDateLiteral: PassID = "sqlDateLiteral"
}

/// Writes a complete date after a comparison word in a query editor as one quoted `'YYYY-MM-DD'` literal.
struct SQLDateLiteralPass: PieceCleaningPass {
    static let id: PassID = .sqlDateLiteral
    // Only the structural laws hold: the digits of a date move into the statement's order.
    static let laws: Set<PassLaw> = [.idempotent, .latinOnly]

    func apply(_ draft: Draft) -> Draft {
        let live = draft.presentIndices
        let text = live.map { draft.words[$0].text }.joined(separator: " ")
        let written = Self.literals(in: text)
        guard written != text, let first = live.first else { return draft }
        var draft = draft
        draft.replace(at: first, with: written, by: Self.id)
        for index in live.dropFirst() { draft.remove(at: index, by: Self.id) }
        return draft
    }

    /// The words that put a date in a comparison slot.
    private static let comparisonWords = "after|before|on|since|until|from|equals|equal to"

    private static let months: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.monthSymbols.map { $0.lowercased() }
    }()
    private static let monthPattern = months.joined(separator: "|")

    /// Month-first ("January 1, 2026"), day-first ("the 1st of January 2026") and numeric ("2026/01/01") dates.
    private static let patterns: [NSRegularExpression] = [
        #"(?:the )?(?<m>\#(monthPattern)) (?<d>\d{1,2})(?:st|nd|rd|th)?,? (?<y>\d{4})"#,
        #"(?:the )?(?<d>\d{1,2})(?:st|nd|rd|th)?(?: of)? (?<m>\#(monthPattern)),? (?<y>\d{4})"#,
        #"(?<y>\d{4})[/-](?<m>\d{1,2})[/-](?<d>\d{1,2})"#,
    ].compactMap {
        try? NSRegularExpression(
            pattern: "(?<![\\w'])(\(comparisonWords)) (?:" + $0 + ")(?![\\w'])", options: [.caseInsensitive])
    }

    /// `text` with every complete date after a comparison word written as a quoted literal.
    static func literals(in text: String) -> String {
        var result = text
        for regex in patterns {
            let whole = NSRange(result.startIndex..., in: result)
            for match in regex.matches(in: result, range: whole).reversed() {
                guard let literal = literal(match, in: result), let range = Range(match.range, in: result),
                    let lead = Range(match.range(at: 1), in: result)
                else { continue }
                result.replaceSubrange(range, with: result[lead] + " " + literal)
            }
        }
        return result
    }

    /// The quoted literal one match spells, or nil when the day is not in the month.
    private static func literal(_ match: NSTextCheckingResult, in text: String) -> String? {
        func group(_ name: String) -> String? {
            let range = match.range(withName: name)
            return range.location == NSNotFound ? nil : Range(range, in: text).map { String(text[$0]) }
        }
        guard let year = group("y").flatMap({ Int($0) }), let day = group("d").flatMap({ Int($0) }),
            let monthText = group("m")
        else { return nil }
        let month = Int(monthText) ?? (months.firstIndex(of: monthText.lowercased()).map { $0 + 1 } ?? 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard (1...12).contains(month),
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let days = calendar.range(of: .day, in: .month, for: first), days.contains(day)
        else { return nil }
        return String(format: "'%04d-%02d-%02d'", year, month, day)
    }
}
