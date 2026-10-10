// Romanised Hindi words by class, held once as data so every pass reads the same vocabulary.
/// The class each romanised Hindi word takes, read from `hindi-words.json`; a word is added by adding its row.
public enum HindiWords {
    /// What a romanised Hindi word does in a sentence.
    public enum WordClass: String, Decodable, Sendable {
        case copula, negation, postposition, conjunction, questionWord, pronoun, possessive, verbStem
        case auxiliary, particle, subject
    }

    /// The classes of the word, in its exact lowercased spelling; empty when it is not listed.
    public static func classes(of word: String) -> Set<WordClass> {
        rowsBySpelling[word.lowercased()]?.classes ?? []
    }

    /// Spellings that carry structure rather than content, leaving out those that are also English content words ("main", "use"); auxiliaries and particles are read only as `grammarWords`.
    public static let functionWords: Set<String> = Set(
        table.rows.filter {
            !$0.english && !$0.classes.subtracting([.verbStem, .auxiliary, .particle]).isEmpty
        }
        .map(\.id))

    /// Spellings that open a fresh clause as an English subject pronoun does.
    public static let subjects: Set<String> = Set(
        table.rows.filter { $0.classes.contains(.subject) }.map(\.id))

    /// Spellings that ask a question, in every listed spelling.
    public static let questionWords: Set<String> = Set(
        table.rows.filter { $0.classes.contains(.questionWord) }.map(\.id))

    /// Spellings that reverse a sentence.
    public static let negations: Set<String> = Set(
        table.rows.filter { $0.classes.contains(.negation) }.map(\.id))

    /// The word a spelling is a variant of ("nahin" is "nahi"), or nil when the spelling is not listed.
    public static func spellingKey(of word: String) -> String? {
        rowsBySpelling[word].map { $0.word ?? $0.id }
    }

    /// Copulas, auxiliaries, postpositions and particles, by sound key: words that tie a sentence together and carry no content.
    package static let grammarWords: Set<String> = Set(
        table.rows.filter { !$0.classes.isDisjoint(with: [.copula, .postposition, .auxiliary, .particle]) }
            .map {
                Romaniser.soundKey($0.id)
            })

    /// Verb stems as sound keys, one per word rather than per spelling.
    public static let verbStems: Set<String> = Set(
        table.rows.filter { $0.classes.contains(.verbStem) && $0.word == nil }.map {
            Romaniser.soundKey($0.id)
        })

    /// Each pronoun case by sound key, to the pronoun it is a case of: "is" is "yah", "use" is "vah".
    public static let pronounCases: [String: String] = Dictionary(
        table.rows.compactMap { row in row.caseOf.map { (Romaniser.soundKey(row.id), $0) } },
        uniquingKeysWith: { first, _ in first })

    /// Every listed romanised spelling.
    public static let spellings: [String] = table.rows.map(\.id)

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("hindi-words", schema: 1, from: .module, fallback: [])

    private static let rowsBySpelling = Dictionary(
        table.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// One romanised spelling, its classes, the word it respells, the pronoun it is a case of, and whether English uses it as a content word.
    struct Row: DataTableRow {
        let id: String
        let classes: Set<WordClass>
        let word: String?
        let caseOf: String?
        let english: Bool

        enum CodingKeys: String, CodingKey { case id, classes, word, caseOf, english }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            classes = try container.decode(Set<WordClass>.self, forKey: .classes)
            word = try container.decodeIfPresent(String.self, forKey: .word)
            caseOf = try container.decodeIfPresent(String.self, forKey: .caseOf)
            english = try container.decodeIfPresent(Bool.self, forKey: .english) ?? false
        }
    }
}
