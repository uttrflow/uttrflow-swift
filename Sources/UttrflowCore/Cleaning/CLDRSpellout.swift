internal import Foundation

/// The English number and ordinal words of a pinned CLDR release, kept to say what the hand tables miss.
package enum CLDRSpellout {
    /// The bundled extract; `Scripts/cldr_extract.py` makes it from the release its manifest entry names.
    static let table = DataTable<Row>.load("cldr-en-spellout", schema: 1, from: .module, fallback: [])

    /// Whether a word names a cardinal or an ordinal.
    enum Kind: String, Decodable, Sendable {
        case cardinal, ordinal
    }

    /// One spelled-out word and the value it stands for.
    struct Row: DataTableRow {
        let id: String
        let value: Int
        let kind: Kind
    }

    /// What the hand tables in `NumberWords` lack and what only they hold, each as a sorted list of words.
    package struct Coverage: Equatable, Sendable {
        /// CLDR words that `NumberWords` does not read to the same value.
        package let missing: [String]
        /// `NumberWords` words that CLDR's English does not have.
        package let handOnly: [String]
    }

    /// Compares the hand tables against the extract.
    package static var coverage: Coverage {
        let missing = table.rows.filter { row in
            switch row.kind {
            case .cardinal: NumberWords.value(of: row.id) != row.value
            case .ordinal: NumberWords.ordinals[row.id] != row.value
            }
        }
        let known = Set(table.rows.map(\.id))
        let hand = Set(NumberWords.units.keys).union(NumberWords.teens.keys).union(NumberWords.tens.keys)
            .union(NumberWords.scales.keys).union(NumberWords.ordinals.keys)
        return Coverage(
            missing: missing.map(\.id).sorted(), handOnly: hand.subtracting(known).sorted())
    }
}
