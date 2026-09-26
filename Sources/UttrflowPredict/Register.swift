/// The measurable facts about where a line is written, computed the same way in every application and never from its name. See `Docs/predict-context.md`.
public struct Register: Sendable, Equatable {
    /// Whether the field holds many lines, where paragraphs are written rather than commands or searches.
    public let isMultiline: Bool
    /// About how long this person's lines here are, in characters, or the screen's lines in a conversation.
    public let typicalLength: Int?
    /// Whether the screen shows people taking turns, by name or by timestamp beside a message box, which the line is then a reply in.
    public let isConversational: Bool
    /// The share of the characters here that are neither letters, digits nor spaces: high for commands, code and queries.
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
        usesSentenceCase: Bool?, writesAddresses: Bool = false, isSearchField: Bool = false
    ) {
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
        return Register(
            isMultiline: situation.isMultiline,
            typicalLength: typical,
            isConversational: conversational,
            symbolShare: symbolShare(of: [situation.preceding ?? "", typed] + own),
            usesSentenceCase: own.isEmpty ? nil : sentenceCaseShare(of: own) >= 0.5,
            // The person's own lines decide where there are any; a combined search-and-address field takes queries too.
            writesAddresses: own.isEmpty ? namesAddressField(situation.field) : addressShare(of: own) >= 0.5,
            isSearchField: namesSearchField(situation.field))
    }

    /// Whether the field's own accessibility name says it takes web addresses: browsers publish "Address and search bar", "Search or enter website name", "Search or enter address" or a URL field, while a postal or email address field never pairs the word with search.
    static func namesAddressField(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("url") || name.contains("website") || name.contains("web address")
            || (name.contains("search") && name.contains("address"))
    }

    /// Whether the field's own accessibility name says it searches: a box called a search or a find is answered from what this person has looked for, never from a guess at what they mean; a filter or a query is not counted, since an editor calls its own field one.
    static func namesSearchField(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("search") || name.contains("find")
    }

    /// Whether the line can only come from what this person has entered here before: a host and a search phrase are both known or unknowable, never inferred. See `Docs/predict-precision.md`.
    public var answersFromHistoryAlone: Bool { writesAddresses || isSearchField }

    /// What the line is, in the word the instruction at the line uses, so the register is stated once more where a small model weighs it most.
    public var kind: String {
        if writesAddresses { return "web address, a host and path and never a command," }
        if symbolShare > Self.symbolicShare { return "command, query or line of code" }
        return isConversational ? "reply" : "line"
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

    /// A reply is always given room for a whole message, however terse this person has been, since a reply cut to a word is no reply.
    public static let replyTokens = 48

    /// Below this many characters a person's typical line says they write tersely, not how long a reply should be, so it is not quoted to the model.
    public static let terseLength = 24

    /// How many tokens a pass may spend: enough for a line the length of this person's lines, never less than a short one, and never less than a whole reply.
    public var maxTokens: Int {
        // Half the typical character count is about twice the tokens the line needs, which leaves room for alternatives.
        let budget: Int
        if let typicalLength {
            budget = min(max(typicalLength / 2, Self.tokenRange.lowerBound), Self.tokenRange.upperBound)
        } else {
            budget = symbolShare > Self.symbolicShare ? 32 : (isConversational ? Self.replyTokens : 64)
        }
        return isConversational ? max(budget, Self.replyTokens) : budget
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
        if symbolShare > Self.symbolicShare {
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
            label.allSatisfy({ $0.isLetter || $0.isNumber || " ()._-'".contains($0) })
        else { return nil }
        return label
    }

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

    /// The share of the visible characters that are neither letters, digits nor whitespace.
    static func symbolShare(of texts: [String]) -> Double {
        var visible = 0
        var symbols = 0
        for character in texts.joined() where !character.isWhitespace {
            visible += 1
            if !character.isLetter, !character.isNumber { symbols += 1 }
        }
        return visible == 0 ? 0 : Double(symbols) / Double(visible)
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
