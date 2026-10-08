/// One technical term: how it is written, how it is said, and where it applies.
public struct TechnicalTerm: DataTableRow, Equatable {
    /// What kind of term it is, which picks the passes that may read it.
    public enum Category: String, Decodable, Sendable, CaseIterable {
        /// A letter-spelt or word-said abbreviation: API, JSON, SQL.
        case acronym
        /// A programming or shell language.
        case language
        /// A program typed at a prompt, or one of its subcommands.
        case command
        /// An open tool, framework or platform named in prose.
        case tool
        /// A programming or systems word an ordinary speller would not expect.
        case concept
        /// A file name or extension.
        case fileFormat
        /// A marker word that opens a code comment: TODO, FIXME.
        case annotation
        /// Letters or words joined by a spoken "and" or "slash" into one token: Q&A, N/A, and/or.
        case joined
    }

    /// The written form, with its casing; unique within the lexicon.
    public let id: String
    /// The ways it is said, each as lower-cased words separated by single spaces.
    public let spoken: [String]
    /// What kind of term it is.
    public let category: Category
    /// Phoneme spellings of the term; empty until a pronunciation source is added.
    public let pronunciations: [String]
    /// The destinations it applies in; nil means every destination.
    public let destinations: Set<Destination>?
    /// Whether the written form, past its leading dot, is also an everyday spoken word: swift, go, lock.
    public let isEveryday: Bool

    /// Whether the term applies where the words are going.
    public func applies(in destination: Destination) -> Bool {
        destinations?.contains(destination) ?? true
    }

    /// Whether its written form, lowercased, is an ordinary word it would claim; a form only ever spelt letter by letter claims one only when it is a function word.
    package func claimsOrdinaryWrittenForm(_ isOrdinary: (String) -> Bool) -> Bool {
        let key = id.lowercased()
        let speltOut = spoken.allSatisfy { $0.split(separator: " ").allSatisfy { $0.count == 1 } }
        return isOrdinary(key) && (!speltOut || FunctionWords.holds(key))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decode(String.self, forKey: .id)
        spoken = try container.decode([String].self, forKey: .spoken)
        category = try container.decode(Category.self, forKey: .category)
        pronunciations = try container.decodeIfPresent([String].self, forKey: .pronunciations) ?? []
        destinations = try container.decodeIfPresent(Set<Destination>.self, forKey: .destinations)
        isEveryday = try container.decodeIfPresent(Bool.self, forKey: .everyday) ?? false
    }

    private enum Key: String, CodingKey {
        case id, spoken, category, pronunciations, destinations, everyday
    }
}

/// Why a lexicon entry cannot ship.
public enum TechnicalTermProblem: Equatable, Sendable {
    /// The entry has no spoken form.
    case unspoken(id: String)
    /// A spoken form is not lower-cased Latin words separated by single spaces.
    case malformedSpoken(id: String, spoken: String)
    /// The written form claims an ordinary word or a spoken form is one, and no destination limits where it applies.
    case ordinaryWithoutDestination(id: String)
    /// The entry lists an empty set of destinations, so it applies nowhere.
    case appliesNowhere(id: String)
    /// The written form is not printable Latin-script characters without spaces.
    case malformedWritten(id: String)
    /// An earlier entry of the same category says the same phrase in a destination this one shares.
    case duplicateSpoken(id: String, spoken: String, earlier: String)
}

/// The shipped technical vocabulary, read from `technical-lexicon.json`; a new term is a row there.
public enum TechnicalLexicon {
    /// The bundled rows; with none loaded every word stays as spoken.
    static let table = DataTable<TechnicalTerm>.load(
        "technical-lexicon", schema: 1, from: .module, fallback: [])

    /// Every term, in file order.
    public static var terms: [TechnicalTerm] { table.rows }

    /// Whether the bundled file was used rather than the empty default.
    public static var isBundled: Bool { table.source == .bundled }

    /// The written form of every program typed at a prompt in `destination`.
    static func commands(in destination: Destination) -> Set<String> {
        Set(terms.filter { $0.category == .command && $0.applies(in: destination) }.map(\.id))
    }

    private static let codeEditorCommands = commands(in: .codeEditor)

    /// Whether heard words, as spoken, open with a program typed at a prompt followed by an argument: "npm run build".
    public static func opensCommandLine(_ heard: [String]) -> Bool {
        guard heard.count >= 2, let first = heard.first else { return false }
        return codeEditorCommands.contains(first)
    }

    /// The entries that cannot ship; `isOrdinary` is the ordinary-word test the dictionary owns.
    public static func problems(
        in terms: [TechnicalTerm], isOrdinary: (String) -> Bool
    ) -> [TechnicalTermProblem] {
        terms.flatMap { problems(of: $0, isOrdinary: isOrdinary) } + collisions(in: terms)
    }

    private static func collisions(in terms: [TechnicalTerm]) -> [TechnicalTermProblem] {
        var found: [TechnicalTermProblem] = []
        for (index, term) in terms.enumerated() {
            let earlier = terms[..<index]
            for phrase in term.spoken {
                let clash = earlier.first { other in
                    other.category == term.category && other.spoken.contains(phrase)
                        && sharesDestination(other, term)
                }
                if let clash {
                    found.append(.duplicateSpoken(id: term.id, spoken: phrase, earlier: clash.id))
                }
            }
        }
        return found
    }

    private static func sharesDestination(_ first: TechnicalTerm, _ second: TechnicalTerm) -> Bool {
        guard let one = first.destinations, let two = second.destinations else { return true }
        return !one.isDisjoint(with: two)
    }

    private static func problems(
        of term: TechnicalTerm, isOrdinary: (String) -> Bool
    ) -> [TechnicalTermProblem] {
        var found: [TechnicalTermProblem] = []
        if !isWellFormedWritten(term.id) { found.append(.malformedWritten(id: term.id)) }
        if term.spoken.isEmpty { found.append(.unspoken(id: term.id)) }
        for phrase in term.spoken where !isWellFormed(phrase) {
            found.append(.malformedSpoken(id: term.id, spoken: phrase))
        }
        if term.destinations?.isEmpty == true { found.append(.appliesNowhere(id: term.id)) }
        let ordinary = term.claimsOrdinaryWrittenForm(isOrdinary) || term.spoken.contains(where: isOrdinary)
        if ordinary && term.destinations == nil { found.append(.ordinaryWithoutDestination(id: term.id)) }
        return found
    }

    private static func isWellFormedWritten(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { ("!"..."~").contains($0) }
    }

    private static func isWellFormed(_ phrase: String) -> Bool {
        let words = phrase.split(separator: " ", omittingEmptySubsequences: false)
        return !words.isEmpty
            && words.allSatisfy { word in
                !word.isEmpty
                    && word.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
            }
    }
}
