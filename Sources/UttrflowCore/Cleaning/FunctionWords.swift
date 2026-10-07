/// The small words a phrase is built from, which carry structure rather than what was said.
public enum FunctionWords {
    /// Whether the word is one of the small words, apostrophes and case aside.
    public static func holds(_ word: String) -> Bool {
        all.contains(word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'"))
    }

    /// Whether the word carries meaning, so a restatement may be anchored on it or replace it.
    public static func isContent(_ word: String) -> Bool { !word.isEmpty && !holds(word) }

    /// Whether a sentence cannot end on the word, since it leads into what follows ("the", "and", "is", "let's").
    public static func leadsOn(_ word: String) -> Bool {
        let key = word.lowercased()
        return leadingOn.contains(key) || Restatement.contractedSubjects.contains(key)
    }

    /// Whether the small word carries meaning the rewrite must keep: who acts, whether it is possible or required, or where it goes.
    public static func isMeaningBearing(_ word: String) -> Bool {
        let key = word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return meaningBearing.contains(key)
    }

    /// Pronouns, modals, copula and perfect aux, and prepositions that set a direction; their removal or substitution changes what was said.
    public static let meaningBearing = words(in: .meaningBearing)

    /// Articles, demonstratives and possessives, which mark the noun after them as a common noun ("my", "the").
    public static let determiners = words(in: .determiner)

    /// Articles and plural demonstratives code is never dictated with, so any of them marks an utterance as prose.
    public static let prose = words(in: .prose)

    /// Articles, possessives, conjunctions, prepositions that take an object, and the copula.
    static let leadingOn = words(in: .leadsOn)

    /// Articles, determiners, prepositions, conjunctions, auxiliaries and pronouns, English and romanised Hindi; dialect stays content.
    public static let all = words(in: .function).union(HindiWords.functionWords)

    /// The bundled word list; a word is added by adding its row to `function-words.json`.
    static let table = DataTable<Row>.load("function-words", schema: 1, from: .module, fallback: [])

    private static func words(in role: Role) -> Set<String> {
        Set(table.rows.filter { $0.roles.contains(role) }.map(\.id))
    }

    /// The lists a small word belongs to.
    enum Role: String, Decodable, Sendable {
        case function, leadsOn, meaningBearing, determiner, prose
    }

    /// One small word and the lists it belongs to.
    struct Row: DataTableRow {
        let id: String
        let roles: Set<Role>
    }
}
