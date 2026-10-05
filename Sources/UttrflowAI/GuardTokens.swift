import UttrflowCore
import UttrflowDictionary

// The guard's token model: grammar tokens, their gaps, identifier parts and one-word spelling joins.
extension MeaningPreservationGuard {
    /// A word of the kept draft or the rewrite, carrying what the grammar checks need to classify it.
    struct GrammarToken: Sendable, Equatable {
        /// The word as written, punctuation trimmed from its edges.
        let text: String
        /// Lowercased with curly apostrophes straightened, the form the function-word set is keyed by.
        let lookup: String
        /// Lowercased with curly apostrophes straightened, the exact spelling used for survival checks.
        let matching: String
        /// Whether the word opens the text or follows a sentence-closing mark.
        let startsSentence: Bool

        /// Whether the checks can read the word at all: Latin script, accents included; Devanagari and the like are left to the base checks.
        var isPlain: Bool { matching.unicodeScalars.allSatisfy(Self.isLatin) }

        /// Whether a scalar is ASCII, a Latin letter with or without its accent, or an accent written apart.
        static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x00...0x7F: true
            case 0x00C0...0x024F, 0x1E00...0x1EFF: scalar.properties.isAlphabetic
            case 0x0300...0x036F: true
            default: false
            }
        }
    }

    /// Whether an identifier is spelled wholly from said words, every part of it one of them and in the order they were said.
    static func isSpelled(_ identifier: String, from said: [GrammarToken]) -> Bool {
        let parts = identifierParts(identifier)
        guard parts.count > 1 else { return false }
        var next = said.startIndex
        for part in parts {
            guard let place = said[next...].firstIndex(where: { survives(part, as: $0) }) else {
                return false
            }
            next = place + 1
        }
        return true
    }

    /// The words an identifier is written from, cut at a camel hump and at anything not a letter or digit.
    static func identifierParts(_ identifier: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for character in identifier where character != "'" && character != "\u{2019}" {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { parts.append(current) }
                current = ""
                previous = nil
                continue
            }
            if character.isUppercase, previous.map({ $0.isLowercase || $0.isNumber }) == true {
                parts.append(current)
                current = ""
            }
            current += character.lowercased()
            previous = character
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Splits on whitespace and hyphens, trimming punctuation and tracking sentence starts.
    static func grammarTokens(_ text: String) -> [GrammarToken] {
        var tokens: [GrammarToken] = []
        var startsSentence = true
        let pieces = withoutThousandsSeparators(text)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
        for raw in pieces {
            let endsSentence = raw.contains { ".!?".contains($0) }
            let trimmed = raw.drop(while: { !$0.isLetter && !$0.isNumber })
            let word = trimmed.reversed().drop(while: { !$0.isLetter && !$0.isNumber }).reversed()
            guard !word.isEmpty else {
                startsSentence = startsSentence || endsSentence
                continue
            }
            let lookup = String(word).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            tokens.append(
                GrammarToken(
                    text: String(word), lookup: lookup,
                    matching: lookup,
                    startsSentence: startsSentence))
            startsSentence = endsSentence
        }
        return joiningOneWordSpellings(tokens)
    }

    /// The text between the words `grammarTokens` reads, one more than there are words, so a mark is found at its place.
    static func grammarTokenGaps(_ text: String) -> [String] {
        var gaps = [""]
        var raw: [GrammarToken] = []
        let pieces = withoutThousandsSeparators(text)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
        for piece in pieces {
            let leading = piece.prefix(while: { !$0.isLetter && !$0.isNumber })
            let trailing = String(
                piece.dropFirst(leading.count).reversed()
                    .prefix(while: { !$0.isLetter && !$0.isNumber }).reversed())
            guard leading.count < piece.count else {
                gaps[gaps.count - 1] += String(piece)
                continue
            }
            gaps[gaps.count - 1] += String(leading)
            raw.append(contentsOf: grammarTokens(String(piece)).prefix(1))
            gaps.append(trailing)
        }
        // A pair read as one word gives up the gap between its halves.
        var joined = [gaps[0]]
        var index = 0
        for token in grammarTokens(text) where index < raw.count {
            index += raw[index].matching == token.matching ? 1 : 2
            joined.append(gaps[min(index, gaps.count - 1)])
        }
        return joined
    }

    /// Two words written apart for one word, keyed by the one word; a listed pair, never a rule about shape.
    static let oneWordSpellings: [String: (first: String, second: String)] = [
        "cannot": ("can", "not")
    ]

    /// Reads a listed pair written apart as its one word, so "can not" and "cannot" are the same word either way round.
    static func joiningOneWordSpellings(_ tokens: [GrammarToken]) -> [GrammarToken] {
        var joined: [GrammarToken] = []
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            let next = index + 1 < tokens.endIndex ? tokens[index + 1] : nil
            if let next, !next.startsSentence,
                let word = oneWordSpellings.first(where: {
                    $0.value.first == token.matching && $0.value.second == next.matching
                })?.key
            {
                joined.append(
                    GrammarToken(
                        text: token.text + next.text, lookup: word, matching: word,
                        startsSentence: token.startsSentence))
                index += 2
                continue
            }
            joined.append(token)
            index += 1
        }
        return joined
    }

    /// A number and a mid-sentence capital are always content; the rest is unless the set below holds it.
    static func isContent(_ token: GrammarToken) -> Bool {
        if token.matching.contains(where: \.isNumber) { return true }
        if !token.startsSentence, token.text.first?.isUppercase == true { return true }
        return !FunctionWords.holds(token.lookup)
    }
}
