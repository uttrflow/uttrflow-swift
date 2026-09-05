import Foundation

extension StringProtocol {
    /// Whether `needle` occurs here ignoring case and accents, which is how every search in the app matches.
    func contains(_ needle: String, ignoringCaseAndAccentsIn locale: Locale) -> Bool {
        range(
            of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
            locale: locale
        ) != nil
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
