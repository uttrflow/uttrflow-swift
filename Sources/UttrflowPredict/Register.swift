/// The measurable facts about where a line is written, computed the same way in every application and never from its name. See `Docs/predict-context.md`.
public struct Register: Sendable, Equatable {
    /// Whether the field holds many lines, where paragraphs are written rather than commands or searches.
    public let isMultiline: Bool
    /// About how long this person's lines here are, in characters, or the screen's lines in a conversation.
    public let typicalLength: Int?
    /// Whether the screen shows a back-and-forth of short turns, which the line is then a reply in.
    public let isConversational: Bool
    /// The share of the characters here that are neither letters, digits nor spaces: high for commands, code and queries.
    public let symbolShare: Double
    /// Whether this person writes in full sentences here, or nothing when they have written nothing here yet.
    public let usesSentenceCase: Bool?
    /// Whether this person's lines here are web addresses, which a bare word then continues into a host, not a command.
    public let writesAddresses: Bool

    public init(
        isMultiline: Bool, typicalLength: Int?, isConversational: Bool, symbolShare: Double,
        usesSentenceCase: Bool?, writesAddresses: Bool = false
    ) {
        self.isMultiline = isMultiline
        self.typicalLength = typicalLength
        self.isConversational = isConversational
        self.symbolShare = symbolShare
        self.usesSentenceCase = usesSentenceCase
        self.writesAddresses = writesAddresses
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
        let conversational = isConversation(screenLines)
        let own = situation.recentLines
        let typical = median(own.map(\.count)) ?? (conversational ? median(screenLines.map(\.count)) : nil)
        return Register(
            isMultiline: situation.isMultiline,
            typicalLength: typical,
            isConversational: conversational,
            symbolShare: symbolShare(of: [situation.preceding ?? "", typed] + own),
            usesSentenceCase: own.isEmpty ? nil : sentenceCaseShare(of: own) >= 0.5,
            writesAddresses: !own.isEmpty && addressShare(of: own) >= 0.5)
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

    /// How many tokens a pass may spend: enough for a line the length of this person's lines, never less than a short one.
    public var maxTokens: Int {
        // Half the typical character count is about twice the tokens the line needs, which leaves room for alternatives.
        guard let typicalLength else {
            if symbolShare > Self.symbolicShare { return 32 }
            return isConversational ? 48 : 64
        }
        return min(max(typicalLength / 2, Self.tokenRange.lowerBound), Self.tokenRange.upperBound)
    }

    /// The facts as short phrases the model reads, so it matches the register instead of guessing it.
    public var hints: [String] {
        var hints = [isMultiline ? "a multi-line field" : "a single-line field"]
        if let typicalLength {
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

    /// Whether the lines read as turns of a conversation: several of them, and mostly short.
    static func isConversation(_ lines: [String]) -> Bool {
        guard lines.count >= conversationLines else { return false }
        let short = lines.filter { $0.count < conversationLineLength }.count
        return Double(short) / Double(lines.count) >= 0.6
    }

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
