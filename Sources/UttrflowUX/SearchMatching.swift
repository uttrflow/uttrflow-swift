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

    /// Whether this text, whole, is `needle` under the same folding as `contains(_:ignoringCaseAndAccentsIn:)`.
    func equals(_ needle: String, ignoringCaseAndAccentsIn locale: Locale) -> Bool {
        let haystack = SearchFolding.folded(self) ?? String(self)
        let needle = SearchFolding.folded(needle) ?? needle
        return haystack.compare(needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            == .orderedSame
    }
}

extension String {
    /// Where `needle` first occurs under the search folding, as a range of this unfolded text.
    func range(of needle: String, ignoringCaseAndAccentsIn locale: Locale) -> Range<String.Index>? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let needle = SearchFolding.folded(needle) ?? needle
        guard let folded = SearchFolding.foldedWithOrigins(self) else {
            return range(of: needle, options: options, range: nil, locale: locale)
        }
        guard let found = folded.text.range(of: needle, options: options, range: nil, locale: locale)
        else { return nil }
        let scalars = folded.text.unicodeScalars
        let lower = scalars.distance(from: scalars.startIndex, to: found.lowerBound)
        let upper = scalars.distance(from: scalars.startIndex, to: found.upperBound)
        return folded.origins[lower]..<folded.origins[upper]
    }
}

/// Typographic punctuation and whitespace, reduced to what a keyboard types.
enum SearchFolding {
    private static let apostrophes: Set<Unicode.Scalar> = ["\u{2018}", "\u{2019}", "\u{201B}", "\u{2032}"]
    private static let quotes: Set<Unicode.Scalar> = ["\u{201C}", "\u{201D}", "\u{201E}", "\u{2033}"]
    private static let dashes: Set<Unicode.Scalar> = [
        "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}",
    ]

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

    /// The folded text with, per folded scalar, where it starts in `text`, plus the end; `nil` if unchanged.
    static func foldedWithOrigins(_ text: String) -> (text: String, origins: [String.Index])? {
        guard folded(text) != nil else { return nil }
        var out = String.UnicodeScalarView()
        var origins: [String.Index] = []
        var previousWasSpace = false
        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if isWhitespace(scalar) {
                if !previousWasSpace {
                    out.append(" ")
                    origins.append(index)
                }
                previousWasSpace = true
            } else {
                previousWasSpace = false
                out.append(straightened(scalar))
                origins.append(index)
            }
            index = scalars.index(after: index)
        }
        origins.append(scalars.endIndex)
        return (String(out), origins)
    }

    /// The keyboard form of one non-whitespace scalar.
    private static func straightened(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard scalar.value >= lowestRewritten else { return scalar }
        if apostrophes.contains(scalar) { return "'" }
        if quotes.contains(scalar) { return "\"" }
        if dashes.contains(scalar) { return "-" }
        return scalar
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
