// The one search rule every list page uses: trimmed, case- and accent-insensitive, blank keeps all.
import Foundation

extension StringProtocol {
    /// Whether `needle` occurs here ignoring case, accents, curly quotes, dash kinds and whitespace runs.
    func contains(_ needle: String, ignoringCaseAndAccentsIn locale: Locale) -> Bool {
        let haystack = SearchFolding.folded(self) ?? String(self)
        let needle = SearchFolding.folded(needle) ?? needle
        return haystack.range(
            of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
            locale: locale
        ) != nil
    }
}

/// Typographic punctuation and whitespace, reduced to what a keyboard types.
enum SearchFolding {
    private static let apostrophes: Set<Unicode.Scalar> = ["\u{2018}", "\u{2019}", "\u{201B}", "\u{2032}"]
    private static let quotes: Set<Unicode.Scalar> = ["\u{201C}", "\u{201D}", "\u{201E}", "\u{2033}"]
    private static let dashes: Set<Unicode.Scalar> = [
        "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}",
    ]

    /// The text with curly quotes straightened, dashes as `-` and whitespace runs as one space; `nil` if unchanged.
    static func folded<S: StringProtocol>(_ text: S) -> String? {
        var needsFolding = false
        var previousWasSpace = false
        for scalar in text.unicodeScalars {
            let isSpace = scalar.properties.isWhitespace
            if apostrophes.contains(scalar) || quotes.contains(scalar) || dashes.contains(scalar)
                || (isSpace && (scalar != " " || previousWasSpace))
            {
                needsFolding = true
                break
            }
            previousWasSpace = isSpace
        }
        guard needsFolding else { return nil }
        var out = String.UnicodeScalarView()
        previousWasSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !previousWasSpace { out.append(" ") }
                previousWasSpace = true
                continue
            }
            previousWasSpace = false
            if apostrophes.contains(scalar) {
                out.append("'")
            } else if quotes.contains(scalar) {
                out.append("\"")
            } else if dashes.contains(scalar) {
                out.append("-")
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }
}

/// The one rule every list page searches by: trimmed, and a blank query keeps everything.
enum SearchQuery {
    /// The query as it is matched, with surrounding whitespace dropped.
    static func needle(in query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The items whose named fields mention the query; all of them when nothing was typed.
    static func matches<Item>(
        _ items: [Item], query: String, locale: Locale, fields: (Item) -> [String?]
    ) -> [Item] {
        let needle = needle(in: query)
        guard !needle.isEmpty else { return items }
        return items.filter { item in
            fields(item).contains { $0?.contains(needle, ignoringCaseAndAccentsIn: locale) == true }
        }
    }
}
