// Attested romanised spellings of one Hindi word, held once as data so every judge of "one word" reads the same sets.
/// The spelling sets read from `romanised-variants.json`; a variant is added by adding it to its word's row.
public enum RomanisedVariants {
    /// The word's most common spelling when the word is listed, otherwise nil; `spelling` is matched lowercased.
    static func canonical(of spelling: String) -> String? {
        canonicalBySpelling[spelling.lowercased()]
    }

    /// `text` with each listed variant written as its word's common spelling, in sentences with at least two Hindi function words; a row marked not rewritable, whose variants are other words ("main", "to"), keeps its spelling.
    public static func canonicalised(_ text: String) -> String {
        guard !rewrites.isEmpty else { return text }
        var output = ""
        var sentence = ""
        func flush() {
            output +=
                isHindi(sentence) ? PreferredSpelling.applied(to: sentence, preferring: rewrites) : sentence
            sentence = ""
        }
        for character in text {
            sentence.append(character)
            if ".!?\n".contains(character) { flush() }
        }
        flush()
        return output
    }

    /// Whether a sentence holds two Hindi function words, in any listed spelling, that English does not also use.
    private static func isHindi(_ sentence: String) -> Bool {
        let words = sentence.split(whereSeparator: { !$0.isLetter }).map { word in
            let spelling = word.lowercased()
            return rewrites[spelling] ?? spelling
        }
        return Set(words).intersection(hindiMarkers).count >= 2
    }

    private static let hindiMarkers = HindiWords.functionWords.subtracting(FunctionWords.english)

    private static let rewrites: [String: String] = Dictionary(
        table.rows.filter(\.rewritable).flatMap { row in row.variants.map { ($0, row.id) } },
        uniquingKeysWith: { first, _ in first })

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("romanised-variants", schema: 1, from: .module, fallback: [])

    private static let canonicalBySpelling: [String: String] = Dictionary(
        table.rows.flatMap { row in ([row.id] + row.variants).map { ($0, row.id) } },
        uniquingKeysWith: { first, _ in first })

    /// One Hindi word as it is most often typed, with the other spellings people type for it.
    struct Row: DataTableRow {
        let id: String
        let variants: [String]
        /// False when a variant is also another word, so the spelling alone cannot say which one is spoken.
        let rewritable: Bool

        enum CodingKeys: String, CodingKey { case id, variants, rewritable }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            variants = try container.decode([String].self, forKey: .variants)
            rewritable = try container.decodeIfPresent(Bool.self, forKey: .rewritable) ?? true
        }
    }
}
