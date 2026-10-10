/// Words said before or between numbers that say how to write them, read from `number-cues.json`.
public enum NumberCues {
    /// What a cue word says about the number after it.
    public enum Cue: String, Decodable, Sendable {
        /// Digit groups a spoken "dot" joins are an address, version or decimal.
        case dotted
        /// A run of digit words is a code or a number to dial, not a count.
        case digitRun
        /// A word between two numbers that makes them one group written in one form.
        case coordinator
        /// A coordinator that joins only a rising pair, so "ten to six" stays a clock reading.
        case range
        /// A larger unit that a smaller one may follow as one measure.
        case measureLead
        /// A smaller unit that closes a two-part measure.
        case measureTail
        /// An arithmetic operator; its `symbol` replaces it between numbers in arithmetic.
        case `operator`
        /// A word after which a lone digit is a numeral, digit groups run together, and no separator is used.
        case designator
    }

    /// The cue words that say `cue`.
    public static func words(for cue: Cue) -> Set<String> {
        Set(table.rows.filter { $0.cues.contains(cue) }.map(\.id))
    }

    /// Each spoken operator as its words, and the symbol that replaces it.
    public static let operators: [[String]: String] = Dictionary(
        table.rows.compactMap { row in
            guard row.cues.contains(.operator), let symbol = row.symbol else { return nil }
            return (row.id.split(separator: " ").map(String.init), symbol)
        },
        uniquingKeysWith: { first, _ in first })

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("number-cues", schema: 1, from: .module, fallback: [])

    /// One cue word and what it says.
    struct Row: DataTableRow {
        let id: String
        let cues: Set<Cue>
        /// The symbol that replaces an `operator` row.
        let symbol: String?
    }
}
