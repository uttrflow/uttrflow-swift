// The words the recogniser spells as one token, read from `recogniser-words.json`.

/// Every lowercase word the recogniser's tokenizer spells as one token, most frequent first; see `Docs/ordinary-words.md`.
package enum RecogniserWords {
    /// The lowercase words, built once from the table.
    package static let all = Set(table.rows.map(\.id))

    /// The word's frequency rank, 1 for the most frequent; nil for a word the table lacks, case as in `all`.
    package static func rank(of word: String) -> Int? { ranks[word] }

    /// Each word's 1-based position in the table, whose rows are in the tokenizer's merge order.
    private static let ranks = Dictionary(
        uniqueKeysWithValues: table.rows.enumerated().map { ($0.element.id, $0.offset + 1) })

    /// The bundled table, written by `Scripts/derive_recogniser_words.py`; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load(
        "recogniser-words", schema: 2, from: .module, fallback: [], limits: limits)

    /// Room for the whole tokenizer vocabulary, which no derivation can exceed.
    static let limits = DataTableLimits(maxBytes: 512 * 1_024, maxRows: 52_000)

    /// One word.
    struct Row: DataTableRow {
        let id: String
    }
}
