// The words the recogniser spells as one token, read from `recogniser-words.json`.

/// Every lowercase word the speech recogniser's tokenizer spells as a single token. See `Docs/ordinary-words.md`.
package enum RecogniserWords {
    /// The lowercase words, built once from the table.
    package static let all = Set(table.rows.map(\.id))

    /// The bundled table, written by `Scripts/derive_recogniser_words.py`; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load(
        "recogniser-words", schema: 1, from: .module, fallback: [], limits: limits)

    /// Room for the whole tokenizer vocabulary, which no derivation can exceed.
    static let limits = DataTableLimits(maxBytes: 512 * 1_024, maxRows: 52_000)

    /// One word.
    struct Row: DataTableRow {
        let id: String
    }
}
