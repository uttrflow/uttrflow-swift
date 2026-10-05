/// The one owner of whether a word's final full stop is part of the word or ends the sentence.
public enum Abbreviations {
    /// What an abbreviation is, which decides whether its stop may also end a sentence.
    public enum Kind: String, Decodable, Sendable {
        case title, leadIn, latin, time, month, unit, nameSuffix, corporate, reference, acronym, initial

        /// Titles lead into a name and Latin lead-ins into an example, so neither ends a sentence.
        var leadsOn: Bool { self == .title || self == .leadIn }
    }

    /// What kind of abbreviation the word is, case aside, read without its trailing stop; nil when it is not one.
    public static func kind(of word: String) -> Kind? {
        let key = word.lowercased()
        if let row = rows[key] { return row.kind }
        if isDottedAcronym(key) { return .acronym }
        if key.count == 1, key.first?.isLetter == true { return .initial }
        return nil
    }

    /// Whether a full stop after the word belongs to it whatever follows, so a mark added after it keeps the stop.
    public static func ownsStop(_ word: String) -> Bool {
        let key = word.lowercased()
        if let row = rows[key] { return !row.alsoAWord }
        return isDottedAcronym(key)
    }

    /// Whether the written word closes its sentence, given the word after it when there is one.
    public static func endsSentence(_ text: String, followedBy next: String?) -> Bool {
        let shape = WordShape(text)
        guard shape.endsSentence else { return false }
        guard shape.suffix.last(where: { ".!?…।॥".contains($0) }) == ".", let kind = kind(of: shape.core)
        else {
            return true
        }
        if kind.leadsOn { return false }
        // With nothing after it, a stop that only an abbreviation could own ("etc.", "p.m.") keeps the sentence open.
        guard let next else { return !ownsStop(shape.core) }
        guard let first = WordShape(next).core.first else { return true }
        // A form that is also a word ("no", "co") is the abbreviation only before a number, as in "No. 5".
        if rows[shape.core.lowercased()]?.alsoAWord == true { return !first.isNumber }
        return first.isUppercase
    }

    /// Letters in runs of one or two split by inner stops, as in "U.S" or "a.m".
    private static func isDottedAcronym(_ key: String) -> Bool {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count > 1 && parts.allSatisfy { (1...2).contains($0.count) && $0.allSatisfy(\.isLetter) }
    }

    /// The bundled rows by lower-cased written form; a form is added by adding its row to `abbreviations.json`.
    static let table = DataTable<Row>.load("abbreviations", schema: 1, from: .module, fallback: [])

    private static let rows: [String: Row] = Dictionary(table.rows.map { ($0.id, $0) }) { first, _ in first }

    /// One written abbreviation, its kind, and whether it is also an everyday word ("no", "co").
    struct Row: DataTableRow {
        let id: String
        let kind: Kind
        let alsoAWord: Bool

        private enum CodingKeys: String, CodingKey { case id, kind, alsoAWord }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try container.decode(Kind.self, forKey: .kind)
            alsoAWord = try container.decodeIfPresent(Bool.self, forKey: .alsoAWord) ?? false
        }
    }
}
