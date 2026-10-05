/// Which side of its name a spoken mark goes, which is what decides where a mention of it could stand.
public enum SpokenMarkKind: String, Decodable, Sendable, Equatable {
    /// Goes on the word before it: a comma, a full stop, a question mark.
    case trailing
    /// Joins the words on both sides of it: a hyphen, a dash.
    case joining
    /// Opens a quotation, so it goes on the word after it and needs nothing before it.
    case opening
    /// Closes one, so it goes on the word before it as a trailing mark does.
    case closing
    /// Stands as a word of its own between the words on both sides of it: an ampersand.
    case standalone
    /// Goes on the word after it without opening a quotation: an at sign, a hash sign.
    case leading

    /// Whether the mark goes on the word after its name rather than on the one before.
    public var attachesAfter: Bool { self == .opening || self == .leading }
}

/// One phrase said as an instruction rather than as words, and what it writes.
public struct SpokenCommand: DataTableRow, Equatable {
    /// What a command does with the words around it, which picks the pass that reads it.
    public enum Action: String, Decodable, Sendable {
        /// A punctuation mark written onto a neighbouring word.
        case mark
        /// A line break, paragraph break or list item.
        case layout
        /// A symbol written in place of its name in executable code.
        case codeSymbol
        /// A case style, named by `text`, applied to the words the row's reach covers.
        case casing
        /// An option marker written before the word after it at a command line; `destinations` are where every dash is one.
        case flag
        /// A lead-in kept as spoken, with `text` written onto its last word when the clause goes on after it.
        case leadIn
        /// An edit said under the editing key: the words up to `until` are found in the last insertion and replaced by the rest.
        case replace
    }

    /// How many of the following words a casing command covers.
    public enum Reach: String, Decodable, Sendable {
        /// Every word up to a spoken clause mark or the end of the clause: an identifier.
        case clause
        /// The one word after the command.
        case word
        /// Every word up to the row's closing phrase, which is said and dropped.
        case span
    }

    /// The row's stable name.
    public let id: String
    /// The spoken phrase, as lower-cased word keys.
    public let words: [String]
    /// What the command does.
    public let action: Action
    /// The text it writes.
    public let text: String
    /// Where a mark goes relative to its name; trailing when the row does not say.
    public let placement: SpokenMarkKind
    /// Whether the command writes a list item, so it applies only where lists are laid out.
    public let requiresLists: Bool
    /// The destinations it is enabled in; nil means every destination.
    public let destinations: Set<Destination>?
    /// The words a casing command covers; a clause when the row does not say.
    public let reach: Reach
    /// The phrase that ends a span, as lower-cased word keys; empty for any other reach.
    public let until: [String]

    /// Whether the command is enabled where the words are going.
    public func isEnabled(in destination: Destination) -> Bool {
        destinations?.contains(destination) ?? true
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decode(String.self, forKey: .id)
        words = try container.decode([String].self, forKey: .words)
        action = try container.decode(Action.self, forKey: .action)
        text = try container.decode(String.self, forKey: .text)
        placement = try container.decodeIfPresent(SpokenMarkKind.self, forKey: .placement) ?? .trailing
        requiresLists = try container.decodeIfPresent(Bool.self, forKey: .requiresLists) ?? false
        destinations = try container.decodeIfPresent(Set<Destination>.self, forKey: .destinations)
        reach = try container.decodeIfPresent(Reach.self, forKey: .reach) ?? .clause
        until = try container.decodeIfPresent([String].self, forKey: .until) ?? []
    }

    private enum Key: String, CodingKey {
        case id, words, action, text, placement, requiresLists, destinations, reach, until
    }
}

/// Every spoken command, read from `spoken-commands.json`; a new command is a row there.
public enum SpokenCommands {
    /// The bundled rows; with none loaded every phrase stays as spoken.
    static let table = DataTable<SpokenCommand>.load(
        "spoken-commands", schema: 1, from: .module, fallback: [])

    /// Every row, in file order.
    public static var all: [SpokenCommand] { table.rows }
    /// Punctuation said by name, in file order so a longer name is tried before a shorter one.
    public static let marks = rows(.mark)
    /// Layout said by name.
    public static let layout = rows(.layout)
    /// Symbols said by name in code: the code rows, and the bracket marks, which code writes as bare symbols.
    public static let codeSymbols = rows(.codeSymbol) + marks.filter { isBracket($0.text) }
    /// Case styles said by name, in file order so a longer phrase is tried before a shorter one.
    public static let casings = rows(.casing)
    /// Option markers said by name, longest first.
    public static let flags = rows(.flag).sorted { $0.words.count > $1.words.count }
    /// Phrases that introduce what follows them, such as a list.
    public static let leadIns = rows(.leadIn)
    /// Edits that replace words in the last insertion, said only under the editing key.
    public static let replacements = rows(.replace)

    /// Whether `text` is a single bracket, opening or closing.
    public static func isBracket(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        return WordShape.bracketOpeners[character] != nil
            || WordShape.bracketOpeners.values.contains(character)
    }

    /// The marks that open a quotation or a bracket.
    public static let openings = marks.filter { $0.placement == .opening }
    /// The marks that close a quotation or a bracket.
    public static let closings = marks.filter { $0.placement == .closing }

    private static func rows(_ action: SpokenCommand.Action) -> [SpokenCommand] {
        table.rows.filter { $0.action == action }
    }
}
