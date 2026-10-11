/// English words said as an aside at the edge of a sentence ("actually", "anyway"), read from `aside-words.json`.
package enum AsideWords {
    /// Where in a sentence a word stands apart from the clause.
    package enum Position: String, Decodable, Sendable {
        case opening, closing
    }

    /// Whether the word, case aside, is an aside where it stands.
    package static func holds(_ word: String, at position: Position) -> Bool {
        (position == .opening ? opening : closing).contains(word.lowercased())
    }

    /// Whether the words around an aside are a Hindi clause: a listed Hindi function word, and more of them than English ones.
    package static func areHindiClause(_ words: [String]) -> Bool {
        let keys = words.map { $0.lowercased() }
        let hindi = keys.filter(HindiWords.functionWords.contains).count
        let english = keys.filter {
            FunctionWords.english.contains($0) && !HindiWords.functionWords.contains($0)
        }
        return hindi > 0 && hindi > english.count
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("aside-words", schema: 1, from: .module, fallback: [])

    private static let opening = Set(table.rows.filter { $0.positions.contains(.opening) }.map(\.id))
    private static let closing = Set(table.rows.filter { $0.positions.contains(.closing) }.map(\.id))

    /// One aside and the edges of a sentence it is set off at.
    struct Row: DataTableRow {
        let id: String
        let positions: Set<Position>
    }
}
