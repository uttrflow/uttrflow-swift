/// The words a spoken spreadsheet formula is read by, from `formula-words.json`.
package enum FormulaWords {
    /// What a row names.
    enum Kind: String, Decodable, Sendable {
        /// A worksheet function, written in capitals where it is followed by an opening bracket.
        case function
        /// A spoken phrase and the mark it is written as.
        case `operator`
    }

    /// The function names a formula can call, lower case.
    package static let functions = Set(table.rows.filter { $0.kind == .function }.map(\.id))

    /// The comparison and arithmetic phrases and their marks, longest first so "greater than or equal to" is not read as "greater than".
    package static let operators: [(words: [String], mark: String)] =
        table.rows.compactMap { row in
            guard row.kind == .operator, let words = row.words, let mark = row.mark else { return nil }
            return (words, mark)
        }.sorted { $0.words.count > $1.words.count }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("formula-words", schema: 1, from: .module, fallback: [])

    /// One function name, or one operator phrase with its mark.
    struct Row: DataTableRow {
        let id: String
        let kind: Kind
        let words: [String]?
        let mark: String?
    }
}
