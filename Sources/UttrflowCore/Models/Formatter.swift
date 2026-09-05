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

/// What one kind of place wants done to the words: decisions, never code. See `Docs/cleanup-design.md`.
public struct Formatter: Sendable, Equatable {
    public let destination: Destination
    public let firstWord: FirstWordPolicy
    public let terminalStop: TerminalStopPolicy

    public init(destination: Destination, firstWord: FirstWordPolicy, terminalStop: TerminalStopPolicy) {
        self.destination = destination
        self.firstWord = firstWord
        self.terminalStop = terminalStop
    }

    /// The shipped value for every destination; code stays `.never` until comments are told apart.
    public static let registry: [Destination: Formatter] = [
        .document: Formatter(destination: .document, firstWord: .fromInsertionPoint, terminalStop: .always),
        .spreadsheet: Formatter(destination: .spreadsheet, firstWord: .asSpoken, terminalStop: .never),
        .sqlEditor: Formatter(destination: .sqlEditor, firstWord: .fromInsertionPoint, terminalStop: .always),
        .codeEditor: Formatter(
            destination: .codeEditor, firstWord: .fromInsertionPoint, terminalStop: .never),
        .messaging: Formatter(
            destination: .messaging, firstWord: .fromInsertionPoint,
            terminalStop: .offForShortMessages(sentences: 2)),
        .email: Formatter(destination: .email, firstWord: .fromInsertionPoint, terminalStop: .always),
        .plain: Formatter(destination: .plain, firstWord: .fromInsertionPoint, terminalStop: .always),
    ]

    /// The formatter for a destination, falling back to plain text's for one the registry lacks.
    public static func standard(for destination: Destination) -> Formatter {
        registry[destination]
            ?? Formatter(destination: .plain, firstWord: .fromInsertionPoint, terminalStop: .always)
    }
}
