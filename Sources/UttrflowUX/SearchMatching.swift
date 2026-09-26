// The one search rule every list page uses: trimmed, case- and accent-insensitive, blank keeps all.
import Foundation

extension StringProtocol {
    /// Whether `needle` occurs here ignoring case, accents, curly quotes, dash kinds and whitespace runs.
    func contains(_ needle: String, ignoringCaseAndAccentsIn locale: Locale) -> Bool {
        SearchFolding.contains(
            SearchFolding.folded(needle) ?? needle,
            inFolded: SearchFolding.folded(self) ?? String(self), locale: locale)
    }
}

/// Typographic punctuation and whitespace, reduced to what a keyboard types.
enum SearchFolding {
    private static let apostrophes: Set<Unicode.Scalar> = ["\u{2018}", "\u{2019}", "\u{201B}", "\u{2032}"]
    private static let quotes: Set<Unicode.Scalar> = ["\u{201C}", "\u{201D}", "\u{201E}", "\u{2033}"]
    private static let dashes: Set<Unicode.Scalar> = [
        "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}",
    ]

    /// Whether an already-folded needle occurs in an already-folded haystack, ignoring case and accents.
    static func contains(_ needle: String, inFolded haystack: String, locale: Locale) -> Bool {
        haystack.range(
            of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
            locale: locale
        ) != nil
    }

    /// The lowest scalar this folding rewrites, below which only whitespace can need it.
    private static let lowestRewritten: UInt32 = 0x2010

    /// Whether this scalar is whitespace: by value inside ASCII, and outside it only where Unicode puts one, since the property lookup costs more than the rest of the scan.
    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value >= 0x80 else {
            return scalar.value == 0x20 || (scalar.value >= 0x09 && scalar.value <= 0x0D)
        }
        switch scalar.value {
        case 0x85, 0xA0, 0x1680, 0x2000...0x202F, 0x205F, 0x3000:
            return scalar.properties.isWhitespace
        default: return false
        }
    }

    /// Whether this scalar is one of the marks straightened here; every one of them is well above ASCII.
    private static func isRewritten(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value >= lowestRewritten else { return false }
        return apostrophes.contains(scalar) || quotes.contains(scalar) || dashes.contains(scalar)
    }

    /// The text with curly quotes straightened, dashes as `-` and whitespace runs as one space; `nil` if unchanged.
    static func folded<S: StringProtocol>(_ text: S) -> String? {
        var needsFolding = false
        var previousWasSpace = false
        for scalar in text.unicodeScalars {
            let isSpace = isWhitespace(scalar)
            if isRewritten(scalar) || (isSpace && (scalar != " " || previousWasSpace)) {
                needsFolding = true
                break
            }
            previousWasSpace = isSpace
        }
        guard needsFolding else { return nil }
        var out = String.UnicodeScalarView()
        previousWasSpace = false
        for scalar in text.unicodeScalars {
            if isWhitespace(scalar) {
                if !previousWasSpace { out.append(" ") }
                previousWasSpace = true
                continue
            }
            previousWasSpace = false
            guard scalar.value >= lowestRewritten else {
                out.append(scalar)
                continue
            }
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
