/// How the first word is cased.
public enum FirstWordPolicy: Sendable, Equatable {
    /// A capital, unless the caret sits mid-sentence.
    case fromInsertionPoint
    case alwaysCapital
    /// Whatever case the word was heard in.
    case asSpoken
}

/// Whether the last sentence is given a full stop.
public enum TerminalStopPolicy: Sendable, Equatable, Codable {
    case always
    /// No full stop is added, and one the tidier or the model put there is taken back.
    case never
    /// Withheld when the text holds this many sentences or fewer.
    case offForShortMessages(sentences: Int)

    /// The policy in a one-line field of no known purpose, which holds a value: one sentence there gets no stop.
    var inOneLineField: TerminalStopPolicy {
        self == .always ? .offForShortMessages(sentences: 1) : self
    }
}

/// How a numeral's digits are grouped, which is a separate question from which numbers become numerals.
public enum DigitGrouping: Sendable, Equatable {
    /// A separator every three digits from ten thousand up, as prose wants: 12,000.
    case thousands
    /// A comma after the last three digits and every two before them, from one lakh up: 1,50,000.
    case indian
    /// The digits and nothing between them, as anything that will be parsed wants: 12000.
    case none

    /// The size of each group of digits, read from the right.
    var groupSizes: (last: Int, rest: Int)? {
        switch self {
        case .thousands: (3, 3)
        case .indian: (3, 2)
        case .none: nil
        }
    }

    /// Whether a written numeral carries this grouping, so "1,50,000" reads as Indian and "150,000" does not.
    public func matches(_ spelling: String) -> Bool {
        guard let sizes = groupSizes else { return !spelling.contains(",") }
        let groups = spelling.split(separator: ",", omittingEmptySubsequences: false)
        guard groups.count >= 2, let last = groups.last, last.count == sizes.last,
            (1...sizes.rest).contains(groups[0].count)
        else { return false }
        return groups.dropFirst().dropLast().allSatisfy { $0.count == sizes.rest }
    }
}

/// How the person writes numbers, which travels with them rather than with the place the text lands.
public struct NumberStyle: Sendable, Equatable {
    /// How a numeral's digits are grouped where the place leaves that to the reader's habit.
    public let grouping: DigitGrouping

    public init(grouping: DigitGrouping) {
        self.grouping = grouping
    }

    /// Commas every three digits, the style until a setting says otherwise.
    public static let standard = NumberStyle(grouping: .thousands)
}

/// Counting the sentences a text holds, which is what the short-message rule is asked about.
public enum SentenceCount {
    /// How many sentences the text holds, counting a last one that has no mark yet.
    public static func of(_ text: String) -> Int {
        var count = 0
        var openSentence = false
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if SentenceMarks.ends.contains(character) {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // A stop between two digits is a decimal point, not the end of a sentence.
                let insideNumber = character == "." && (next?.isNumber ?? false)
                let endsHere = next == nil || (next?.isWhitespace ?? false)
                if openSentence, endsHere, !insideNumber {
                    count += 1
                    openSentence = false
                }
            } else if !character.isWhitespace {
                openSentence = true
            }
        }
        return count + (openSentence ? 1 : 0)
    }
}

/// Which spoken numbers a place wants written as numerals.
public enum NumberPolicy: Sendable, Equatable {
    /// Every number is a numeral, zero to nine included, as a cell or an editor wants.
    case always
    /// Ten and up are numerals; zero to nine stay words unless they sit in a number phrase.
    case fromTen
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
    /// Which spoken numbers become numerals here.
    public let numbers: NumberPolicy
    /// How a numeral's digits are grouped here, which somewhere machine-read cannot leave to prose habits.
    public let digits: DigitGrouping
    /// The style rules and worked examples the model is shown for this place.
    public let promptBlock: PromptBlockID
    /// What this place does with the text once it lands.
    public let consequence: Consequence

    public init(
        destination: Destination, firstWord: FirstWordPolicy, terminalStop: TerminalStopPolicy,
        layout: LayoutPolicy, grammar: GrammarPolicy, numbers: NumberPolicy = .fromTen,
        digits: DigitGrouping = .thousands, promptBlock: PromptBlockID, consequence: Consequence = .stores
    ) {
        self.destination = destination
        self.firstWord = firstWord
        self.terminalStop = terminalStop
        self.layout = layout
        self.grammar = grammar
        self.numbers = numbers
        self.digits = digits
        self.promptBlock = promptBlock
        self.consequence = consequence
    }

    /// The shipped value for every destination; code stays `.never` until comments are told apart.
    public static let registry: [Destination: DestinationFormatter] = [
        .document: DestinationFormatter(
            destination: .document, firstWord: .fromInsertionPoint, terminalStop: .always,
            layout: [.paragraphs, .lists], grammar: .repair, numbers: .fromTen,
            promptBlock: "document"),
        .spreadsheet: DestinationFormatter(
            destination: .spreadsheet, firstWord: .asSpoken, terminalStop: .never, layout: .singleLine,
            grammar: .asSpoken, numbers: .always, promptBlock: "spreadsheet"),
        .sqlEditor: DestinationFormatter(
            destination: .sqlEditor, firstWord: .fromInsertionPoint, terminalStop: .always,
            layout: .preserveNewlines, grammar: .asSpoken, numbers: .always, digits: .none,
            promptBlock: "sqlEditor"),
        .codeEditor: DestinationFormatter(
            destination: .codeEditor, firstWord: .fromInsertionPoint, terminalStop: .never,
            layout: .preserveNewlines, grammar: .asSpoken, numbers: .always, digits: .none,
            promptBlock: "codeEditor"),
        .terminal: DestinationFormatter(
            destination: .terminal, firstWord: .asSpoken, terminalStop: .never,
            layout: .singleLine, grammar: .asSpoken, numbers: .always, digits: .none,
            promptBlock: "terminal", consequence: .executes),
        .messaging: DestinationFormatter(
            destination: .messaging, firstWord: .fromInsertionPoint,
            terminalStop: .offForShortMessages(sentences: 2), layout: .paragraphs,
            grammar: .asSpoken, numbers: .fromTen, promptBlock: "messaging", consequence: .sends),
        .email: DestinationFormatter(
            destination: .email, firstWord: .fromInsertionPoint, terminalStop: .always,
            layout: [.paragraphs, .lists], grammar: .repair, numbers: .fromTen,
            promptBlock: "email"),
        .plain: DestinationFormatter(
            destination: .plain, firstWord: .fromInsertionPoint, terminalStop: .always,
            layout: [.paragraphs, .lists], grammar: .repair, numbers: .fromTen, promptBlock: "plain"),
    ]

    /// Whether a line opening with a program typed at a prompt keeps its heard case: source, never a comment's prose.
    public var keepsCommandCase: Bool { destination == .codeEditor && !layout.contains(.paragraphs) }

    /// Whether this place's first-word or stop policy would still change `text`, so an answer returning it unchanged did no work.
    public func owesFormatting(_ text: String) -> Bool {
        let first = text.first.map(String.init) ?? ""
        let owesCapital = firstWord != .asSpoken && first != first.uppercased()
        let owesStop = terminalStop != .never && !Self.hasClauseMark(text)
        return owesCapital && owesStop
    }

    /// Whether `text` holds a clause mark; one between two digits, as in "2.4.1" or "9,000", belongs to the number.
    private static func hasClauseMark(_ text: String) -> Bool {
        let characters = Array(text)
        return characters.indices.contains { index in
            guard ".!?;,".contains(characters[index]) else { return false }
            let inNumber =
                index > 0 && index + 1 < characters.count
                && characters[index - 1].isNumber && characters[index + 1].isNumber
            return !inNumber
        }
    }

    /// The formatter for a destination, falling back to plain text's for one the registry lacks.
    public static func standard(for destination: Destination) -> DestinationFormatter {
        registry[destination]
            ?? DestinationFormatter(
                destination: .plain, firstWord: .fromInsertionPoint, terminalStop: .always,
                layout: .paragraphs, grammar: .repair, numbers: .fromTen,
                promptBlock: "plain")
    }

    /// The destination formatter with an app rule's terminal-stop exception, when that rule still applies.
    public static func standard(for situation: Situation) -> DestinationFormatter {
        let base = standard(for: situation.destination)
        let preceding = situation.insertion.precedingText
        if situation.destination == .codeEditor {
            let region = situation.intent.region
            if region == .prose { return proseInCodeEditor(base) }
            // A statement opens no sentence, so source takes its first word as spoken, as a terminal does.
            if region.isCode, preceding != nil { return withFirstWord(.asSpoken, base) }
        }
        if situation.destination == .email, let header = emailHeader(situation.intent.fieldRole, base) {
            return header
        }
        let rule = DestinationClassifier.rule(for: situation.app)
            .flatMap { $0.destination == situation.destination ? $0 : nil }
        let ruleStop = rule?.terminalStop
        let role = situation.app.accessibilityRole
        let isSearch = role == "AXSearchField" || rule?.field == .search
        let isSingleLine = situation.app.isMultiline == false || role == "AXTextField" || isSearch
        guard ruleStop != nil || isSingleLine else { return base }
        return DestinationFormatter(
            destination: base.destination,
            firstWord: isSearch ? .asSpoken : base.firstWord,
            terminalStop: isSearch
                ? .never
                : (ruleStop ?? (isSingleLine ? base.terminalStop.inOneLineField : base.terminalStop)),
            layout: isSingleLine ? .singleLine : base.layout,
            grammar: base.grammar, numbers: base.numbers, digits: base.digits,
            promptBlock: base.promptBlock, consequence: isSearch ? .navigates : base.consequence)
    }

    /// A recipient or subject field's one-line, stopless formatter; `nil` keeps the email policy for any other field.
    private static func emailHeader(_ role: FieldRole, _ base: DestinationFormatter) -> DestinationFormatter?
    {
        let firstWord: FirstWordPolicy
        switch role {
        case .recipient: firstWord = .asSpoken
        case .subject: firstWord = base.firstWord
        default: return nil
        }
        return DestinationFormatter(
            destination: base.destination, firstWord: firstWord, terminalStop: .never,
            layout: .singleLine, grammar: base.grammar, numbers: base.numbers, digits: base.digits,
            promptBlock: base.promptBlock, consequence: base.consequence)
    }

    /// The same formatter with another first-word policy.
    private static func withFirstWord(
        _ firstWord: FirstWordPolicy, _ base: DestinationFormatter
    )
        -> DestinationFormatter
    {
        DestinationFormatter(
            destination: base.destination, firstWord: firstWord, terminalStop: base.terminalStop,
            layout: base.layout, grammar: base.grammar, numbers: base.numbers, digits: base.digits,
            promptBlock: base.promptBlock, consequence: base.consequence)
    }

    /// A code editor's formatter with a document's stops and lists, for prose in a Markdown or text file.
    private static func proseInCodeEditor(_ base: DestinationFormatter) -> DestinationFormatter {
        DestinationFormatter(
            destination: base.destination, firstWord: base.firstWord, terminalStop: .always,
            layout: [.paragraphs, .lists], grammar: base.grammar, numbers: base.numbers, digits: base.digits,
            promptBlock: base.promptBlock, consequence: base.consequence)
    }
}
