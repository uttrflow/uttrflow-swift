/// Kinship and honorific words said in place of a name ("Mom said", "Papa ko"), read from `kinship-words.json`.
public enum KinshipWords {
    /// The languages a kinship word is said in.
    public enum Language: String, Decodable, Sendable {
        case en, hi
    }

    /// Whether the word, case and a possessive "'s" aside, is a kinship word that can stand for a name.
    public static func holds(_ word: String) -> Bool {
        let key = word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return words.contains(key.hasSuffix("'s") ? String(key.dropLast(2)) : key)
    }

    /// Whether a word before a kinship word makes it a common noun: an article, a demonstrative or a possessive.
    public static func marksCommonNoun(_ word: String) -> Bool {
        let key = word.lowercased()
        return FunctionWords.determiners.contains(key) || HindiWords.classes(of: key).contains(.possessive)
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("kinship-words", schema: 1, from: .module, fallback: [])

    private static let words = Set(table.rows.map(\.id))

    /// The kinship words said in Hindi, romanised.
    public static let hindiWords: [String] = table.rows.filter { $0.languages.contains(.hi) }.map(\.id)

    /// One kinship word and the languages it is said in.
    struct Row: DataTableRow {
        let id: String
        let languages: Set<Language>
    }
}
