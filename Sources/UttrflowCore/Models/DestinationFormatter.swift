/// How the first word is cased.
public enum FirstWordPolicy: Sendable, Equatable {
    /// A capital, unless the caret sits mid-sentence.
    case fromInsertionPoint
    case alwaysCapital
    /// Whatever case the word was heard in.
    case asSpoken
}

/// Whether the last sentence is given a full stop.
public enum TerminalStopPolicy: Sendable, Equatable {
    case always
    /// No full stop is added, and one the tidier or the model put there is taken back.
    case never
    /// Withheld when the text holds this many sentences or fewer.
    case offForShortMessages(sentences: Int)
}

/// How much grammar a place wants repaired.
public enum GrammarPolicy: Sendable, Equatable {
    /// A slip speech left behind is fixed, changing only the form of a word the speaker said.
    case repair
    /// The words go out with the grammar they were spoken in.
    case asSpoken
}

/// How line breaks in the text are laid out: paragraphs and lists, kept as they are, or none at all.
public struct LayoutPolicy: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Every paragraph ends with a stop, and so does the last sentence, whatever line breaks the text holds.
    public static let paragraphs = LayoutPolicy(rawValue: 1 << 0)
    /// A spoken list is laid out as one; an item never gets a stop.
    public static let lists = LayoutPolicy(rawValue: 1 << 1)
    /// Line breaks are kept as given and a text holding one gets no stop, as dictated code wants.
    public static let preserveNewlines = LayoutPolicy(rawValue: 1 << 2)
    /// Every line break becomes a space, as a spreadsheet cell wants.
    public static let singleLine = LayoutPolicy(rawValue: 1 << 3)
}

/// What one kind of place wants done to the words: decisions, never code. See `Docs/cleanup-design.md`.
public struct DestinationFormatter: Sendable, Equatable {
    public let destination: Destination
    public let firstWord: FirstWordPolicy
    public let terminalStop: TerminalStopPolicy
    public let layout: LayoutPolicy
    /// Whether grammar slips are repaired here or the words go out as spoken.
    public let grammar: GrammarPolicy
    /// The style rules and worked examples the model is shown for this place.
    public let promptBlock: PromptBlockID

    public init(
        destination: Destination, firstWord: FirstWordPolicy, terminalStop: TerminalStopPolicy,
        layout: LayoutPolicy, grammar: GrammarPolicy, promptBlock: PromptBlockID
    ) {
        self.destination = destination
        self.firstWord = firstWord
        self.terminalStop = terminalStop
        self.layout = layout
        self.grammar = grammar
        self.promptBlock = promptBlock
    }

    /// The shipped value for every destination; code stays `.never` until comments are told apart.
    public static let registry: [Destination: DestinationFormatter] = [
        .document: DestinationFormatter(
            destination: .document, firstWord: .fromInsertionPoint, terminalStop: .always,
            layout: [.paragraphs, .lists], grammar: .repair, promptBlock: "document"),
        .spreadsheet: DestinationFormatter(
            destination: .spreadsheet, firstWord: .asSpoken, terminalStop: .never, layout: .singleLine,
            grammar: .asSpoken, promptBlock: "spreadsheet"),
        .sqlEditor: DestinationFormatter(
            destination: .sqlEditor, firstWord: .fromInsertionPoint, terminalStop: .always,
            layout: .preserveNewlines, grammar: .asSpoken, promptBlock: "sqlEditor"),
        .codeEditor: DestinationFormatter(
            destination: .codeEditor, firstWord: .fromInsertionPoint, terminalStop: .never,
            layout: .preserveNewlines, grammar: .asSpoken, promptBlock: "codeEditor"),
        .messaging: DestinationFormatter(
            destination: .messaging, firstWord: .fromInsertionPoint,
            terminalStop: .offForShortMessages(sentences: 2), layout: .paragraphs,
            grammar: .asSpoken, promptBlock: "messaging"),
        .email: DestinationFormatter(
            destination: .email, firstWord: .fromInsertionPoint, terminalStop: .always,
            layout: [.paragraphs, .lists], grammar: .repair, promptBlock: "email"),
        .plain: DestinationFormatter(
            destination: .plain, firstWord: .fromInsertionPoint, terminalStop: .always, layout: .paragraphs,
            grammar: .repair, promptBlock: "plain"),
    ]

    /// The formatter for a destination, falling back to plain text's for one the registry lacks.
    public static func standard(for destination: Destination) -> DestinationFormatter {
        registry[destination]
            ?? DestinationFormatter(
                destination: .plain, firstWord: .fromInsertionPoint, terminalStop: .always,
                layout: .paragraphs, grammar: .repair,
                promptBlock: "plain")
    }
}
