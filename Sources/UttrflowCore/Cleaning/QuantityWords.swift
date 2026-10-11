/// The amount and ordinal words that sit beside `NumberWords`, read from `quantity-words.json`.
package enum QuantityWords {
    /// The lists a quantity word can belong to.
    enum List: String, Decodable, Sendable {
        /// A word that states an amount without being a cardinal, as in "half" and "dozen".
        case quantity
        /// A word a scorer reads as a number although no digit spells it, as in "third" and "percent".
        case numeral
    }

    /// Amount words that are not cardinals.
    package static let quantities = words(in: .quantity)

    /// Words read as numbers beyond the cardinals.
    package static let numerals = words(in: .numeral)

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("quantity-words", schema: 1, from: .module, fallback: [])

    private static func words(in list: List) -> Set<String> {
        Set(table.rows.filter { $0.lists.contains(list) }.map(\.id))
    }

    /// One word and the lists it belongs to.
    struct Row: DataTableRow {
        let id: String
        let lists: Set<List>
    }
}
