public import UttrflowCore

/// One spoken-to-cleaned pair the model is shown, with the situation lines it is shown under.
public struct WorkedExample: Sendable, Equatable {
    /// The "Typed into:" line, without its label, or `nil` for an example with no place.
    public let typedInto: String?
    /// The text before the caret, or `nil` for an example that starts a sentence.
    public let caret: String?
    public let spoken: String
    public let cleaned: String

    public init(typedInto: String? = nil, caret: String? = nil, spoken: String, cleaned: String) {
        self.typedInto = typedInto
        self.caret = caret
        self.spoken = spoken
        self.cleaned = cleaned
    }

    /// The example as the model reads it, in the shape the situation block uses.
    public var rendered: String {
        var lines: [String] = []
        if let typedInto { lines.append("\(AppContextDescriber.label) \(typedInto)") }
        if let caret { lines.append("\(PromptBuilder.caretLabel) \"\(caret)\"") }
        lines.append("Spoken: \"\(spoken)\"")
        lines.append("Cleaned: \"\(cleaned)\"")
        return lines.joined(separator: "\n")
    }

    /// The two sentences a corpus case must not reuse.
    public var sentences: [String] { [spoken, cleaned] }
}

/// The style rules and worked examples for one kind of place: decisions, never code.
public struct PromptBlock: Sendable, Equatable {
    public let id: PromptBlockID
    /// The heading and two to four bullet lines, as the model reads them.
    public let rules: String
    /// At most two, and only where the place's layout or final stop differs from the contract's examples.
    public let examples: [WorkedExample]

    public init(id: PromptBlockID, rules: String, examples: [WorkedExample]) {
        self.id = id
        self.rules = rules
        self.examples = examples
    }
}

/// The shipped block for every destination. `Docs/bakeoff.md` records why an example is never a corpus case.
public enum PromptBlocks {
    public static let standard: [PromptBlockID: PromptBlock] = Dictionary(
        uniqueKeysWithValues: [document, spreadsheet, sqlEditor, codeEditor, messaging, email, plain].map {
            ($0.id, $0)
        })

    static let document = PromptBlock(
        id: "document",
        rules: """
            In a document:
            - full sentences; keep the breaks given, and a list only where one was spoken
            - fix a grammar slip: "there is three" → "there are three", "a apple" → "an apple", \
            a drifting tense
            - change only the form of a word the speaker said, never the words; dialect stays — \
            "gonna", "ain't", a double negative
            """,
        examples: [
            WorkedExample(
                spoken: "she have went home",
                cleaned: "She has gone home.")
        ])

    static let spreadsheet = PromptBlock(
        id: "spreadsheet",
        rules: """
            In a spreadsheet cell:
            - one line for one cell, with no full stop at the end
            - numbers as numerals, units as spoken
            - a label stays a label and a value stays a value; never write a formula
            """,
        examples: [
            WorkedExample(
                spoken: "forty two units shipped in week nine",
                cleaned: "42 units shipped in week 9"),
            WorkedExample(
                spoken: "average handling time in minutes",
                cleaned: "average handling time in minutes"),
        ])

    static let sqlEditor = PromptBlock(
        id: "sqlEditor",
        rules: """
            In a SQL editor:
            - prose stays prose: a sentence about a query is a sentence, never a query
            - spell table, column and function names as the screen spells them
            - numerals for numbers; end a sentence with a full stop
            """,
        examples: [])

    static let codeEditor = PromptBlock(
        id: "codeEditor",
        rules: """
            In a code editor:
            - spell identifiers as the screen spells them, and never invent one
            - keep every line break in the input; do not join lines, and add none
            - no full stop at the end
            """,
        examples: [
            WorkedExample(
                typedInto: "a code editor (Xcode), Router.swift",
                spoken: "handle the timeout first\nthen retry once with backoff",
                cleaned: "Handle the timeout first\nthen retry once with backoff")
        ])

    static let messaging = PromptBlock(
        id: "messaging",
        rules: """
            In a chat message:
            - commas and capitals, but no full stop after a message of one or two sentences
            - a question still ends with a question mark
            - keep the greeting, the name and the tone exactly as spoken
            """,
        examples: [
            WorkedExample(
                spoken: "ain't no rush grab me a seat",
                cleaned: "Ain't no rush, grab me a seat"),
            WorkedExample(
                spoken: "did the build go green",
                cleaned: "Did the build go green?"),
        ])

    static let email = PromptBlock(
        id: "email",
        rules: """
            In an email:
            - full sentences and paragraphs; keep the greeting, the sign-off and every break as given
            - fix a grammar slip: "there is three" → "there are three", "have went" → \
            "have gone", "a apple" → "an apple", a drifting tense
            - change only the form of a word the speaker said, never the words; dialect stays — \
            "gonna", "ain't", a double negative
            """,
        examples: [])

    static let plain = PromptBlock(
        id: "plain",
        rules: """
            In plain text:
            - full sentences; end with a full stop, question or exclamation mark
            - keep every line break given, and add none
            - fix a grammar slip: "there is three" → "there are three", "have went" → \
            "have gone", "a apple" → "an apple", a drifting tense
            - change only the form of a word the speaker said, never the words; dialect stays — \
            "gonna", "ain't", a double negative
            """,
        examples: [])
}
