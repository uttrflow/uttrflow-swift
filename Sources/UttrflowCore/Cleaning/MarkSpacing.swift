// Which side of its neighbours each punctuation mark sits on, held once as data so every pass reads the same rule.
/// The side each mark goes on, read from `mark-spacing.json`; a mark is added by adding its row.
package enum MarkSpacing {
    /// The side `mark` goes on, or nil when the mark is not listed or its side depends on position, as a straight quote's does.
    static func kind(of mark: Character) -> SpokenMarkKind? {
        kindByMark[mark]
    }

    /// Whether `mark` goes on the word before it with no space: a comma, a full stop, a closing bracket.
    package static func attachesBefore(_ mark: Character) -> Bool {
        guard let kind = kind(of: mark) else { return false }
        return kind == .trailing || kind == .closing
    }

    /// Whether a joining `mark` is set apart by a space on each side, as an em dash is, rather than glued between its words, as a hyphen is.
    package static func spacesJoin(_ mark: Character) -> Bool {
        spacedJoins.contains(mark)
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("mark-spacing", schema: 1, from: .module, fallback: [])

    private static let kindByMark: [Character: SpokenMarkKind] = Dictionary(
        table.rows.compactMap { row in row.id.count == 1 ? row.id.first.map { ($0, row.kind) } : nil },
        uniquingKeysWith: { first, _ in first })

    private static let spacedJoins: Set<Character> = Set(
        table.rows.compactMap { row in row.kind == .joining && row.spaced == true ? row.id.first : nil })

    /// One mark and the side it goes on.
    struct Row: DataTableRow {
        let id: String
        let kind: SpokenMarkKind
        /// For a joining mark, whether a space goes on each side of it; nil for every other kind.
        let spaced: Bool?
    }
}
