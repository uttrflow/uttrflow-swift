// When a query finds a tag: the reduction a tag shares with an alias, and whole or prefix, never inside.
import Foundation

/// How closely a query names one of a clip's tags; the case order is the order of precedence.
enum PanelTagMatch: Int, Sendable, Comparable {
    /// The query is the whole tag.
    case whole
    /// The query begins the tag.
    case prefix

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The one place that decides when a query finds a tag, so a tag never matches inside a word.
enum PanelTags {
    /// The shortest query compared with tags; one character would begin too many of them.
    static let shortestQuery = 2

    /// A tag reduced to what identifies it: no leading `#`, then the reduction an alias gets.
    static func handle(_ text: String, locale: Locale) -> String {
        PanelAlias.handle(String(text.drop { $0 == "#" }), locale: locale)
    }

    /// The closest any of `tags` comes to `needle`; `nil` for a query with a space or under two characters.
    static func match(_ needle: String, in tags: [String], locale: Locale) -> PanelTagMatch? {
        guard !tags.isEmpty, !needle.contains(where: \.isWhitespace) else { return nil }
        let typed = handle(needle, locale: locale)
        guard typed.count >= shortestQuery else { return nil }
        return tags.compactMap { tag -> PanelTagMatch? in
            let held = handle(tag, locale: locale)
            if held == typed { return .whole }
            return held.hasPrefix(typed) ? .prefix : nil
        }.min()
    }
}
