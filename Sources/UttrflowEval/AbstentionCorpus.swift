// Invented prose full of notation words, dictated into technical apps where none of it may become notation.
public import UttrflowCore

extension EvaluationCorpus {
    // MARK: Abstention. See Docs/formatting-matrix.md.

    /// Every abstention case: each family's sentences dictated at each of its regions.
    public static let abstention: [EvaluationCase] =
        AbstentionFamily.allCases.flatMap { family in
            family.sentences.flatMap { sentence in
                family.regions.map { $0.dictating(sentence, in: family) }
            }
        }
}

/// A kind of technical app whose notation words a speaker also uses as ordinary English.
public enum AbstentionFamily: String, Sendable, CaseIterable {
    case sql
    case source

    /// Where the words go in this family's app.
    public var destination: Destination {
        switch self {
        case .sql: .sqlEditor
        case .source: .codeEditor
        }
    }

    /// The places within a file the caret can sit, each a different context for the same sentence.
    var regions: [AbstentionRegion] {
        switch self {
        case .sql:
            [
                .init(name: "code", document: "report.sql", preceding: "SELECT id FROM orders;\n"),
                .init(name: "comment", document: "report.sql", preceding: "-- "),
                .init(name: "string", document: "report.sql", preceding: "UPDATE orders SET note = '"),
            ]
        case .source:
            [
                .init(name: "code", document: "notes.swift", preceding: "let total = 0\n"),
                .init(name: "comment", document: "notes.swift", preceding: "let total = 0 // "),
                .init(name: "string", document: "notes.swift", preceding: "let message = \""),
                .init(name: "docstring", document: "notes.py", preceding: "def greet():\n    \"\"\""),
            ]
        }
    }

    /// Ordinary sentences, each a slug and its words, that use this family's notation words as English.
    var sentences: [(slug: String, spoken: String)] {
        switch self {
        case .sql:
            [
                ("select-seat", "select a seat from the front row and sit down"),
                ("star-player", "the star player came from the north and joined the team"),
                ("order-group", "order the books by colour and group the maps by size"),
                ("join-where", "we join the walk where the river bends"),
                ("insert-update", "insert the letter into the envelope and update the guest list"),
                ("gold-star", "the gold star from the teacher made her day"),
                ("delete-photos", "delete the old photos from the phone and keep the new ones"),
                ("table-window", "the table by the window is free from noon"),
                ("count-limit", "count the votes and limit the speeches to a few minutes"),
                ("set-drop", "set the table and drop the keys in the bowl"),
            ]
        case .source:
            [
                ("star-dot", "the star of the show put a dot on the map"),
                ("dash-shop", "make a quick dash to the shop before it shuts"),
                ("flour-equals", "a cup of flour equals a bowl of oats in this recipe"),
                ("arrow-sign", "follow the arrow on the sign to reach the car park"),
                ("trial-period", "the trial period ends before the summer holidays"),
                ("slash-open", "slash the prices and open the doors early on sale day"),
                ("close-window", "please close the window and open the curtains"),
                ("open-bracket", "the judges open bracket play on Friday after lunch"),
                ("close-bracket", "it was a close bracket race all the way to the final"),
                ("open-brace", "workers fixed the open brace under the old bridge"),
                ("close-brace", "the nurse fitted a close brace around his knee"),
                ("open-paren", "her letter has an open paren that never closes"),
                ("open-parenthesis", "the novel leaves an open parenthesis around the war years"),
                ("close-paren", "a close paren was missing from the note she sent"),
                ("close-parenthesis", "a close parenthesis ends the aside in his speech"),
                ("open-parentheses", "the editor left the open parentheses in the draft"),
                ("close-parentheses", "the close parentheses were missing from the list"),
                ("underscore", "these results underscore the need for rest"),
                ("colon-semicolon", "the teacher said a semicolon is rarer than a colon"),
                ("comma-butterfly", "a comma butterfly landed on the fence"),
            ]
        }
    }
}

/// One place a caret can sit in a family's file, named for the case ids.
struct AbstentionRegion: Sendable {
    let name: String
    let document: String
    let preceding: String

    /// The sentence dictated at this region, expected back as the same words with no notation added.
    func dictating(_ sentence: (slug: String, spoken: String), in family: AbstentionFamily) -> EvaluationCase
    {
        let words = sentence.spoken.split(separator: " ").map(String.init)
        let symbols = Set(SpokenCommands.codeSymbols.map(\.text))
        return EvaluationCase(
            id: "abstain-\(family.rawValue)-\(sentence.slug)-\(name)", category: .technical,
            spoken: sentence.spoken,
            expected: sentence.spoken.prefix(1).uppercased() + sentence.spoken.dropFirst() + ".",
            mustKeep: words.filter { $0.count > 3 },
            context: AppContext(documentName: document, precedingText: preceding),
            mustNotAdd: symbols.filter { $0 != "," && $0 != "." }.sorted(),
            destination: family.destination, classes: [.abstention], origin: .synthetic, addedFor: 3781)
    }
}
