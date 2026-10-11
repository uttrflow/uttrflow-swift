/// The SQL words `SQLPosition` reads by spelling, read from `sql-words.json`.
enum SQLWords {
    /// The lists a SQL word can belong to.
    enum List: String, Decodable, Sendable {
        /// A word that ends an alias slot, so the word after a table is not taken as its alias.
        case aliasStopper
        /// A keyword that has a cased spelling and counts toward the statement's keyword case.
        case keyword
    }

    /// Words that end an alias slot.
    static let aliasStoppers = words(in: .aliasStopper)

    /// Keywords that count toward the statement's keyword case.
    static let keywords = words(in: .keyword)

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("sql-words", schema: 1, from: .module, fallback: [])

    private static func words(in list: List) -> Set<String> {
        Set(table.rows.filter { $0.lists.contains(list) }.map(\.id))
    }

    /// One SQL word and the lists it belongs to.
    struct Row: DataTableRow {
        let id: String
        let lists: Set<List>
    }
}
