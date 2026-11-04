/// The small words the series and lettered-item layout reads, by the list each belongs to, read from `layout-series-words.json`.
package enum LayoutSeriesWords {
    /// The words before "the following" that let it announce a series; a preposition before it makes it a time span.
    package static let announcers = words(in: .announcer)

    /// Nouns that make "the following three" a span of time or a count, not a series.
    package static let measures = words(in: .measure)

    /// Plural nouns that do not end in "s"; a cue counting them announces a series just as "items" does.
    package static let irregularPlurals = words(in: .irregularPlural)

    /// Words that open a clause, not an item: a series running into one has not ended.
    package static let clauseOpeners = words(in: .clauseOpener)

    /// Verbs that make "the following three items are ..." a statement, whose first word is no member of the series.
    package static let copulas = words(in: .copula)

    /// The words that name a part of a text, which a letter or a roman numeral then numbers.
    package static let labelWords = words(in: .labelWord)

    /// Words that put a label word inside a noun phrase, so "the item a customer buys" is not a label.
    package static let nounPhraseOpeners = words(in: .nounPhraseOpener)

    /// Words that join two labelled items without being an item.
    package static let joiners = words(in: .joiner)

    /// The roman numerals a lettered list may count in, in order.
    package static let romans: [String] = table.rows.filter { $0.roles.contains(.roman) }
        .sorted { ($0.order ?? 0) < ($1.order ?? 0) }.map(\.id)

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("layout-series-words", schema: 1, from: .module, fallback: [])

    private static func words(in role: Role) -> Set<String> {
        Set(table.rows.filter { $0.roles.contains(role) }.map(\.id))
    }

    /// The lists a word belongs to.
    enum Role: String, Decodable, Sendable {
        case announcer, measure, irregularPlural, clauseOpener, copula, labelWord, nounPhraseOpener, joiner,
            roman
    }

    /// One word and the lists it belongs to; a roman numeral also says where it stands in the count.
    struct Row: DataTableRow {
        let id: String
        let roles: Set<Role>
        let order: Int?
    }
}
