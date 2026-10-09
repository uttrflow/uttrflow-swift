// What a one-line field asks for, read from the words of its label against `field-kinds.json`.

/// The kind of value a field's label names: a name, an address, a date and the other kinds `FieldRole` holds.
enum FieldLabelKinds {
    /// The role a field takes once its label is read: a one-line or unknown field takes the kind its label names; any other role stands.
    static func role(structural: FieldRole, label: String?) -> FieldRole {
        guard structural == .singleLine || structural == .unknown, let label, let named = kind(of: label)
        else { return structural }
        return named
    }

    /// The one kind a label names, longest phrase first, weak yielding to strong; `nil` for none, two strong or two joined.
    static func kind(of label: String) -> FieldRole? {
        let words = label.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(
            String.init)
        var strong = Set<FieldRole>()
        var weak = Set<FieldRole>()
        var joined = false
        var index = 0
        while index < words.count {
            guard let (row, length) = longestPhrase(in: words, at: index) else {
                index += 1
                continue
            }
            switch (row.cue, row.kind) {
            case (.joiner, _): joined = true
            case (.strong, let kind?): strong.insert(kind)
            case (.weak, let kind?): weak.insert(kind)
            default: break
            }
            index += length
        }
        if joined && strong.count + weak.count > 1 { return nil }
        if strong.count == 1 { return strong.first }
        return strong.isEmpty && weak.count == 1 ? weak.first : nil
    }

    /// The longest phrase in the table that starts at `index`, with the number of words it covers.
    private static func longestPhrase(in words: [String], at index: Int) -> (Row, Int)? {
        for length in stride(from: min(longestPhraseLength, words.count - index), through: 1, by: -1) {
            if let row = phrases[words[index..<(index + length)].joined(separator: " ")] {
                return (row, length)
            }
        }
        return nil
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("field-kinds", schema: 1, from: .module, fallback: [])

    /// The kinds a label may name; any other role in the table is ignored.
    static let labelKinds: Set<FieldRole> = [
        .name, .address, .number, .date, .email, .phone, .postalCode, .webAddress, .title,
    ]

    private static let phrases: [String: Row] = Dictionary(
        uniqueKeysWithValues: table.rows
            .filter { $0.cue == .joiner || $0.kind.map(labelKinds.contains) == true }
            .map { ($0.id, $0) })

    private static let longestPhraseLength = phrases.keys.map { $0.split(separator: " ").count }.max() ?? 0

    /// How a phrase counts: a `strong` kind, a `weak` kind that yields to a strong one, or a `joiner` between two.
    enum Cue: String, Decodable, Sendable {
        case strong, weak, joiner
    }

    /// The languages a label phrase is written in.
    enum Language: String, Decodable, Sendable {
        case en, hi
    }

    /// One label phrase, in lowercase words separated by one space, and what it says about the field.
    struct Row: DataTableRow {
        let id: String
        let kind: FieldRole?
        let cue: Cue
        let languages: Set<Language>
    }
}
