/// Sound-alike words whose swap changes what a sentence says, read from `meaning-swaps.json`.
package enum MeaningSwaps {
    /// Whether `heard` and `candidate` are two words of one row, in either order.
    package static func areSwaps(_ heard: String, _ candidate: String) -> Bool {
        pairs.contains([heard, candidate])
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("meaning-swaps", schema: 1, from: .module, fallback: [])

    /// Each row's two words, as a set so the order never matters.
    private static let pairs: Set<Set<String>> = Set(table.rows.map { Set($0.words) })

    /// Two words that sound alike and mean different things.
    struct Row: DataTableRow {
        let id: String
        let words: [String]
    }
}
