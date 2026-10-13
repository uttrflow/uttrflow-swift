/// The lower-case words that join a surname to what comes before it ("van", "de", "bin"), read from `name-particles.json`.
package enum NameParticles {
    /// Whether the word, case aside, is a name particle, which keeps the case it was said in.
    package static func holds(_ word: String) -> Bool { words.contains(word.lowercased()) }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("name-particles", schema: 1, from: .module, fallback: [])

    private static let words = Set(table.rows.map(\.id))

    /// One particle.
    struct Row: DataTableRow {
        let id: String
    }
}
