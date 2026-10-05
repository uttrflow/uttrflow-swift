public import UttrflowCore

// The formatting class each bullet line of the model's instructions asks for, so a line with no owner fails a test.

/// What one bullet line of the prompt asks the model to do.
public enum PromptLineAsk: Sendable, Equatable {
    /// It asks for these formatting classes.
    case formats([FormattingClass])
    /// It repairs a word's form, which no formatting class covers and no pass writes.
    case repairsWords([FormattingClass])
    /// It only protects the spoken words and asks for no formatting.
    case keepsWords

    /// The formatting classes the line asks for.
    public var classes: [FormattingClass] {
        switch self {
        case .formats(let classes), .repairsWords(let classes): classes
        case .keepsWords: []
        }
    }
}

/// One bullet line's tag: where it is, the words it starts with, and what it asks for.
public struct PromptLineTag: Sendable, Equatable {
    /// The block the line is in, or `nil` for the contract every block is appended to.
    public let block: PromptBlockID?
    /// The start of the bullet, which matches exactly one bullet in its scope.
    public let opening: String
    public let ask: PromptLineAsk

    public init(_ block: PromptBlockID?, _ opening: String, _ ask: PromptLineAsk) {
        self.block = block
        self.opening = opening
        self.ask = ask
    }

    /// The classes this line asks for that a cleaning pass owns alone, so the model should not be asked.
    public var rulesOwnedClasses: [FormattingClass] {
        ask.classes.filter { $0.ownership.owner == .rules }
    }
}

/// The tag of every bullet line in the shipped contract and blocks.
public enum PromptLineTags {
    /// The bullet lines of a prompt text: each line that starts with a dash, without its indentation.
    public static func bullets(in text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            $0.hasPrefix("- ")
        }
    }

    public static let all: [PromptLineTag] = [
        PromptLineTag(nil, "- remove fillers", .formats([.corrections])),
        PromptLineTag(nil, "- when a speaker explicitly corrects", .formats([.corrections])),
        PromptLineTag(
            nil, "- fix punctuation, capitalisation",
            .repairsWords([.sentenceBoundaries, .commas, .capitalisationAndTokens])),
        PromptLineTag(nil, "- keep every other word said", .keepsWords),
        PromptLineTag(nil, "- keep technical terms and units", .formats([.capitalisationAndTokens])),
        PromptLineTag(nil, "- Write only English in the Latin alphabet", .formats([.hinglish])),
        PromptLineTag(nil, "- never invent or change", .keepsWords),
        PromptLineTag(nil, "- when unsure", .keepsWords),

        PromptLineTag(
            "document", "- full sentences; keep the breaks",
            .formats([.sentenceBoundaries, .paragraphs, .lists])),
        PromptLineTag("document", "- fix a grammar slip", .repairsWords([])),
        PromptLineTag("document", "- change a word's form", .keepsWords),

        PromptLineTag(
            "spreadsheet", "- one line for one cell", .formats([.perDestination, .sentenceBoundaries])),
        PromptLineTag("spreadsheet", "- numbers as numerals", .formats([.numbers])),
        PromptLineTag("spreadsheet", "- a label stays a label", .formats([.perDestination])),

        PromptLineTag("sqlEditor", "- prose stays prose", .formats([.abstention])),
        PromptLineTag("sqlEditor", "- spell table, column", .formats([.capitalisationAndTokens])),
        PromptLineTag("sqlEditor", "- numerals for numbers", .formats([.numbers, .sentenceBoundaries])),

        PromptLineTag("codeEditor", "- spell identifiers", .formats([.codeAndMarkdown])),
        PromptLineTag("codeEditor", "- keep every line break", .formats([.paragraphs])),
        PromptLineTag("codeEditor", "- no full stop at the end", .formats([.perDestination])),

        PromptLineTag("terminal", "- keep the case of every command", .formats([.codeAndMarkdown])),
        PromptLineTag("terminal", "- keep every line break", .formats([.paragraphs])),
        PromptLineTag("terminal", "- no full stop at the end", .formats([.perDestination])),

        PromptLineTag("messaging", "- commas and capitals", .formats([.commas, .perDestination])),
        PromptLineTag("messaging", "- a question still ends", .formats([.questions])),
        PromptLineTag("messaging", "- keep the greeting", .formats([.perDestination, .paragraphs])),

        PromptLineTag("email", "- full stops for body paragraphs", .formats([.perDestination, .commas])),
        PromptLineTag("email", "- at the end only", .formats([.perDestination])),
        PromptLineTag("email", "- fix a grammar slip", .repairsWords([])),
        PromptLineTag("email", "- change a word's form", .keepsWords),

        PromptLineTag("plain", "- full sentences; end with", .formats([.sentenceBoundaries, .questions])),
        PromptLineTag("plain", "- keep every line break", .formats([.paragraphs])),
        PromptLineTag("plain", "- fix a grammar slip", .repairsWords([.capitalisationAndTokens])),
        PromptLineTag("plain", "- change a word's form", .keepsWords),
    ]
}
