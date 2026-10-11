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

/// What the rename sheet's field holds: the name, and the words marked with `#` as tags.
struct PanelLabelDraft: Equatable {
    /// The typed text without its tags, still to be reduced by ``PanelAlias``.
    let name: String
    /// Each tag reduced, in typed order, without repeats.
    let tags: [String]
    /// Whether every tag is short enough and there are not too many.
    let fitsLimits: Bool
}

/// The one place that decides when a query finds a tag, so a tag never matches inside a word.
enum PanelTags {
    /// The shortest query compared with tags; one character would begin too many of them.
    static let shortestQuery = 2

    /// A tag reduced to what identifies it: no leading `#`, then the reduction an alias gets.
    static func handle(_ text: String, locale: Locale) -> String {
        PanelAlias.handle(String(text.drop { $0 == "#" }), locale: locale)
    }

    /// The most tags a clip carries.
    static let maximumCount = 8
    /// The most characters in one tag.
    static let maximumLength = 24

    /// Splits the sheet's text at spaces and commas: words starting with `#` are tags, the rest is the name.
    static func parse(_ draft: String, locale: Locale) -> PanelLabelDraft {
        var name: [Substring] = []
        var tags: [String] = []
        var fits = true
        for word in draft.split(whereSeparator: \.isWhitespace) {
            guard word.first == "#" else {
                name.append(word)
                continue
            }
            for piece in word.split(separator: ",") {
                let tag = handle(String(piece), locale: locale)
                guard !tag.isEmpty, !tags.contains(tag) else { continue }
                fits = fits && tag.count <= maximumLength
                tags.append(tag)
            }
        }
        return PanelLabelDraft(
            name: name.joined(separator: " "), tags: tags,
            fitsLimits: fits && tags.count <= maximumCount)
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
