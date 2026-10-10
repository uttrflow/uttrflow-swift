import Foundation

/// The measurable facts about where a line is written, computed the same way in every application and never from its name. See `Docs/predict-context.md`.
public struct Register: Sendable, Equatable {
    /// Whether the destination table classifies this as a SQL or code editor.
    public let isCodeDestination: Bool
    /// Whether the field holds many lines, where paragraphs are written rather than commands or searches.
    public let isMultiline: Bool
    /// About how long this person's lines here are, in characters, or the screen's lines in a conversation.
    public let typicalLength: Int?
    /// Whether the screen shows people taking turns, by name or by timestamp beside a message box, which the line is then a reply in.
    public let isConversational: Bool
    /// The share of visible characters here that are neither letters, digits nor sentence punctuation: high for commands, code and queries.
    public let symbolShare: Double
    /// Whether this person writes in full sentences here, or nothing when they have written nothing here yet.
    public let usesSentenceCase: Bool?
    /// Whether this person's lines here are web addresses, which a bare word then continues into a host, not a command.
    public let writesAddresses: Bool
    /// Whether the field is a search box, whose next word is what this person has looked for before or nothing at all.
    public let isSearchField: Bool

    /// The facts as a caller already holds them, for a register that is not inferred.
    public init(
        isMultiline: Bool, typicalLength: Int?, isConversational: Bool, symbolShare: Double,
        usesSentenceCase: Bool?, writesAddresses: Bool = false, isSearchField: Bool = false,
        isCodeDestination: Bool = false
    ) {
        self.isCodeDestination = isCodeDestination
        self.isMultiline = isMultiline
        self.typicalLength = typicalLength
        self.isConversational = isConversational
        self.symbolShare = symbolShare
        self.usesSentenceCase = usesSentenceCase
        self.writesAddresses = writesAddresses
        self.isSearchField = isSearchField
    }

    /// Above this share of symbols the text reads as commands, code or queries: shell lines sit near 0.14, prose under 0.06.
    public static let symbolicShare = 0.10

    /// The fewest visible characters needed unless flags or paths already mark command syntax.
    static let minimumSymbolSampleCharacters = 8

    /// A screen needs at least this many lines before it reads as a conversation.
    public static let conversationLines = 3

    /// Lines of a conversation are short; a screen whose lines mostly run longer than this is a document.
    public static let conversationLineLength = 200

    /// The fewest and most tokens one pass may spend, whatever the register says.
    public static let tokenRange = 24...96

    /// Reads the register off one moment: the field, what is on screen, what the person wrote here, what is typed.
    public static func infer(from situation: GenerationSituation, typed: String) -> Register {
        let screenLines = lines(of: situation.surroundings)
        let conversational = isConversation(
            screenLines, field: situation.field, additionalClockLines: situation.timedTurnLines)
        let own = situation.recentLines
        let typical = median(own.map(\.count)) ?? (conversational ? median(screenLines.map(\.count)) : nil)
        let symbols = symbolShare(of: [situation.preceding ?? "", typed] + own)
        // A member access such as `view.al` is shaped like a host, so the typed line alone names an address only outside code.
        let codeLike = symbols > symbolicShare || situation.isCodeDestination
        return Register(
            isMultiline: situation.isMultiline,
            typicalLength: typical,
            isConversational: conversational,
            symbolShare: symbols,
            usesSentenceCase: own.isEmpty ? nil : sentenceCaseShare(of: own) >= 0.5,
            // Labels are page-controlled; they remain prompt context and never choose a history-only register.
            writesAddresses: (looksLikeAddress(typed) && !codeLike) || addressShare(of: own) >= 0.5,
            isSearchField: situation.accessibilityRole == "AXSearchField",
            isCodeDestination: situation.isCodeDestination)
    }

    /// Whether the line can only come from what this person has entered here before: a host and a search phrase are both known or unknowable, never inferred. See `Docs/predict-precision.md`.
    public var answersFromHistoryAlone: Bool { writesAddresses || isSearchField }

    /// What the line is, in the word the instruction at the line uses, so the register is stated once more where a small model weighs it most.
    public var kind: String {
        if writesAddresses { return "web address, a host and path and never a command," }
        if isCodeLike { return "command, query or line of code" }
        return isConversational ? "reply" : "line"
    }

    /// A known editor, or symbolic lines outside a conversation, tell the model it is writing code, a command or a query; links and emoticons in a chat leave it a reply.
    private var isCodeLike: Bool {
        isCodeDestination || (!isConversational && symbolShare > Self.symbolicShare)
    }

    /// The share of the lines shaped like a web address: no spaces, a dot inside, letters after it.
    static func addressShare(of lines: [String]) -> Double {
        guard !lines.isEmpty else { return 0 }
        return Double(lines.filter(looksLikeAddress).count) / Double(lines.count)
    }

    /// Whether one line is a host or a path rather than words: `docs.example.com/guide`, never `git commit -m`.
    static func looksLikeAddress(_ line: String) -> Bool {
        guard !line.contains(where: \.isWhitespace), let dot = line.firstIndex(of: "."),
            dot != line.startIndex, line.index(after: dot) < line.endIndex
        else { return false }
        return line[line.index(after: dot)].isLetter
    }

    /// A reply with no typical length to follow is given room for a whole message.
    public static let replyTokens = 48

    /// Below this many characters a person's typical line says they write tersely, not how long a reply should be, so it is not quoted to the model.
    public static let terseLength = 24

    /// How many tokens a pass may spend: enough for a line the length of this person's lines, never less than a short one.
    public var maxTokens: Int {
        // Half the typical character count is about twice the tokens the line needs, which leaves room for alternatives.
        if let typicalLength {
            return min(max(typicalLength / 2, Self.tokenRange.lowerBound), Self.tokenRange.upperBound)
        }
        return isCodeLike ? 32 : (isConversational ? Self.replyTokens : 64)
    }

    /// Whether a line here is prose, a reply or a document's sentence, which ends at its first sentence end.
    public var endsAtSentence: Bool { !writesAddresses && !isCodeLike }

    /// How many of this person's typical lines a continuation may run to before it is no line of theirs.
    public static let lengthMultiple = 3

    /// The fewest characters a continuation is allowed, so a terse person's line can still be finished by a word or two.
    public static let shortestAllowance = 16

    /// The most characters a continuation may add with no typical length to go by: a reply, a search or an address runs short, a command or a document's line longer.
    public var registerContinuationLimit: Int {
        if writesAddresses || isSearchField { return 80 }
        if isCodeLike { return 120 }
        return isConversational ? 80 : 160
    }

    /// The most characters a continuation may add here: a multiple of this person's typical line, never past the register's own limit.
    public var longestContinuation: Int {
        guard let typicalLength else { return registerContinuationLimit }
        return min(
            registerContinuationLimit, max(typicalLength * Self.lengthMultiple, Self.shortestAllowance))
    }

    /// The facts as short phrases the model reads, so it matches the register instead of guessing it.
    public var hints: [String] {
        var hints = [isMultiline ? "a multi-line field" : "a single-line field"]
        if let typicalLength, !(isConversational && typicalLength < Self.terseLength) {
            hints.append("lines here run about \(typicalLength) characters")
        }
        if isConversational {
            hints.append("a conversation is on screen and the line answers its last message")
        }
        // An address bar's lines are symbolic too, but a bare word there continues into a host, not into a command.
        if writesAddresses {
            hints.append("the lines here are web addresses, so the line continues into a host and path")
            return hints
        }
        if isCodeLike {
            hints.append("the text here is commands, code or queries rather than prose")
            return hints
        }
        // Sentence case only says something about words; a command has neither capitals nor full stops to read.
        switch usesSentenceCase {
        case true?: hints.append("this person writes in full sentences with punctuation")
        case false?: hints.append("this person writes casually, without sentence punctuation")
        case nil: break
        }
        return hints
    }

    /// The non-blank lines of the text, which is how a screen is counted.
    static func lines(of text: String?) -> [String] {
        (text ?? "").split(whereSeparator: \.isNewline).map(String.init).filter {
            $0.contains { !$0.isWhitespace }
        }
    }

    /// Whether the lines read as turns of a conversation, `additionalClockLines` counting stamps the collector cleaned out of `lines` already.
    static func isConversation(_ lines: [String], field: String? = nil, additionalClockLines: Int = 0) -> Bool
    {
        guard lines.count >= conversationLines else { return false }
        let short = lines.filter { $0.count < conversationLineLength }.count
        guard Double(short) / Double(lines.count) >= 0.6 else { return false }
        return hasSpeakerTurns(lines)
            || (namesMessageComposer(field)
                && lines.filter(showsClockTime).count + additionalClockLines >= timedTurns)
    }

    /// A message composer's screen needs at least this many lines stamped with a time of day before it reads as a conversation.
    public static let timedTurns = 2

    /// Whether the lines open with speakers taking turns: enough of them, at least two people, and someone speaking twice.
    static func hasSpeakerTurns(_ lines: [String]) -> Bool {
        let speakers = lines.compactMap(speaker)
        let distinct = Set(speakers)
        return speakers.count >= conversationLines && distinct.count >= 2 && distinct.count < speakers.count
    }

    /// The name a line opens with before a colon, as in "Priya: on my way" or "Neha (PM): confirmed", or nothing when it opens with words or a time.
    static func speaker(of line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let after = line.index(after: colon)
        guard after == line.endIndex || line[after].isWhitespace else { return nil }
        let label = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard let first = label.first, first.isLetter, label.count <= speakerLength,
            label.split(separator: " ").count <= speakerWords,
            label.allSatisfy({ $0.isLetter || $0.isNumber || " ()._-'".contains($0) }),
            !namesField(label), !isDateLabel(label)
        else { return nil }
        return label
    }

    /// Whether a label is a calendar month or weekday followed by a day number.
    static func isDateLabel(_ label: String) -> Bool {
        let words = label.split(whereSeparator: \.isWhitespace)
        guard words.count == 2, let day = Int(words[1]), (1...31).contains(day) else { return false }
        let calendar = Calendar.current
        let calendarNames =
            calendar.monthSymbols + calendar.shortMonthSymbols + calendar.standaloneMonthSymbols
            + calendar.weekdaySymbols + calendar.shortWeekdaySymbols + calendar.standaloneWeekdaySymbols
        return calendarNames.contains { $0.caseInsensitiveCompare(String(words[0])) == .orderedSame }
    }

    /// Whether a label names a field, by its whole text or its head word, so "Expected result" and "Assigned to" are fields.
    static func namesField(_ label: String) -> Bool {
        let lowered = label.lowercased()
        let head = lowered.prefix { $0.isLetter }
        return fieldLabels.contains(lowered) || fieldLabels.contains(String(head))
    }

    /// Words a record, a form, a mail header or a report opens its repeated labels with, which name a field and never a person.
    static let fieldLabels: Set<String> = [
        "actual", "address", "amount", "assigned", "assignee", "attendees", "bcc", "category", "cc",
        "created", "date", "deadline", "description", "due", "email", "end", "environment", "expected",
        "from", "id", "location", "name", "note", "notes", "owner", "phone", "priority", "reported",
        "reporter", "result", "sent", "severity", "start", "status", "steps", "subject", "summary", "tags",
        "time", "title", "to", "total", "type", "updated", "version", "when", "where",
    ]

    /// The longest a speaker's name may run, in characters, before the text before a colon reads as a sentence.
    static let speakerLength = 32

    /// The most words a speaker's name may have, so "Steps to reproduce the crash:" is not a person.
    static let speakerWords = 3

    /// Whether the field's own accessibility name says it composes a message, as chat composers publish ("Message", "Type a message", "Message #platform"), never a mail's body or subject.
    static func namesMessageComposer(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return (name.contains("message") || name.contains("chat"))
            && !name.contains("body") && !name.contains("subject")
    }

    /// Whether the line shows a time of day, "6:38 PM" or "10:31", which is how a chat stamps each message.
    static func showsClockTime(_ line: String) -> Bool {
        let characters = Array(line)
        for index in characters.indices where characters[index] == ":" {
            var hours = 0
            while hours < 3, index - hours - 1 >= 0, isDigit(characters[index - hours - 1]) { hours += 1 }
            var minutes = 0
            while minutes < 3, index + minutes + 1 < characters.count,
                isDigit(characters[index + minutes + 1])
            {
                minutes += 1
            }
            if (1...2).contains(hours), minutes == 2 { return true }
        }
        return false
    }

    /// Whether the character is one of the ASCII digits a clock is written in.
    private static func isDigit(_ character: Character) -> Bool { ("0"..."9").contains(character) }

    /// The middle value, or nothing for no values at all.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Whether a character is drawn as an emoji, which decorates prose and is never a command's symbol.
    static func isPictograph(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    }

    /// The share of visible characters that are neither letters, digits nor prose punctuation; emoji and whitespace are left out.
    static func symbolShare(of texts: [String]) -> Double {
        var visible = 0
        var symbols = 0
        var hasCommandSyntax = false
        for text in texts {
            for line in text.split(whereSeparator: \.isNewline) {
                let commandShaped = isCommandShaped(line)
                hasCommandSyntax = hasCommandSyntax || commandShaped
                for character in line where !character.isWhitespace && !isPictograph(character) {
                    visible += 1
                    let commandPunctuation = commandShaped && isCommandPunctuation(character)
                    if !character.isLetter, !character.isNumber,
                        (!isSentencePunctuation(character) || commandPunctuation)
                    {
                        symbols += 1
                    }
                }
            }
        }
        guard visible >= minimumSymbolSampleCharacters || hasCommandSyntax else { return 0 }
        return Double(symbols) / Double(visible)
    }

    /// Quotes and dots distinguish shell arguments and paths when flags or path separators anchor the line.
    private static func isCommandPunctuation(_ character: Character) -> Bool {
        ".'\"‘’“”".contains(character)
    }

    /// A flag or path separator is enough structure to trust a short line as command or code evidence.
    private static func isCommandShaped(_ line: Substring) -> Bool {
        if line.contains(where: { "/\\|$`=<>;".contains($0) }) { return true }
        return line.split(whereSeparator: \.isWhitespace).contains { token in
            guard token.first == "-" else { return false }
            let flag = token.drop(while: { $0 == "-" })
            return flag.first?.isLetter == true
        }
    }

    /// Sentence punctuation finishes prose and should not make a short reply look like code.
    private static func isSentencePunctuation(_ character: Character) -> Bool {
        if ".,?!'\"‘’“”".contains(character) { return true }
        // Other scripts' commas and stops (`，` `。` `？` `、` `।`) end prose, never a command.
        return character.unicodeScalars.allSatisfy {
            !$0.isASCII && $0.properties.isTerminalPunctuation
        }
    }

    /// The share of the lines that open with a capital and close with sentence punctuation.
    static func sentenceCaseShare(of lines: [String]) -> Double {
        guard !lines.isEmpty else { return 0 }
        let sentences = lines.filter { line in
            guard let first = line.first, let last = line.last else { return false }
            return first.isUppercase && ".!?".contains(last)
        }
        return Double(sentences.count) / Double(lines.count)
    }
}
