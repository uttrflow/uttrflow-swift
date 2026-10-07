/// How much earlier text a spoken edit command acts on, stated once so no command invents its own.
public enum CommandScope: String, Decodable, Sendable, CaseIterable {
    /// The last written word.
    case word
    /// The last clause of the last sentence, read from written clause marks and `ClauseSegmenter`.
    case clause
    /// The last sentence, closed by the stops `Abbreviations.endsSentence` says end one.
    case sentence
    /// The newest insertion, whole.
    case piece
    /// The last dictation: the newest insertion and each one that ends where the next begins.
    case dictation

    /// The scope a bare "delete that" means.
    public static let `default`: CommandScope = .dictation

    /// The written marks that close a clause inside a sentence.
    static let clauseMarks: Set<Character> = [",", ";", ":", "\u{2014}", "\u{2013}"]

    /// The span at the end of `text` the scope covers, with the space before it; nil refuses an empty text.
    public func range(in text: String) -> Range<String.Index>? {
        let tokens = Self.tokens(in: text)
        guard !tokens.isEmpty else { return nil }
        let first: Int
        switch self {
        case .word: first = tokens.count - 1
        case .sentence: first = Self.lastSentenceStart(Self.words(tokens, in: text))
        case .clause: first = Self.lastClauseStart(Self.words(tokens, in: text))
        case .piece, .dictation: first = 0
        }
        let start = first == 0 ? text.startIndex : tokens[first - 1].upperBound
        return start..<text.endIndex
    }

    /// The whitespace-separated words of `text`, as ranges.
    static func tokens(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let open = start { result.append(open..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let open = start { result.append(open..<text.endIndex) }
        return result
    }

    /// Each word of `text` and whether a line break comes before it.
    static func words(_ tokens: [Range<String.Index>], in text: String) -> [(text: String, opensLine: Bool)] {
        tokens.indices.map { index in
            let gapStart = index == 0 ? text.startIndex : tokens[index - 1].upperBound
            return (
                String(text[tokens[index]]),
                text[gapStart..<tokens[index].lowerBound].contains(where: \.isNewline)
            )
        }
    }

    /// The index of the word that opens the last sentence; a line break also opens one.
    static func lastSentenceStart(_ words: [(text: String, opensLine: Bool)]) -> Int {
        let starts = words.indices.dropFirst().filter { index in
            words[index].opensLine
                || (!words[index - 1].opensLine || !isItemNumber(words[index - 1].text))
                    && Abbreviations.endsSentence(words[index - 1].text, followedBy: words[index].text)
        }
        return starts.last ?? 0
    }

    /// Whether a word is a list item's number, as in "2.".
    static func isItemNumber(_ word: String) -> Bool {
        let shape = WordShape(word)
        return shape.suffix == "." && !shape.core.isEmpty && shape.core.allSatisfy(\.isNumber)
    }

    /// The index of the word that opens the last clause of the last sentence.
    static func lastClauseStart(_ words: [(text: String, opensLine: Bool)]) -> Int {
        let sentenceStart = lastSentenceStart(words)
        let sentence = words[sentenceStart...].map(\.text)
        let marked = sentence.indices.dropLast().filter {
            WordShape(sentence[$0]).suffix.contains(where: clauseMarks.contains)
                || sentence[$0].allSatisfy(clauseMarks.contains)
        }.map { $0 + 1 }
        let spoken = ClauseSegmenter.boundaries(in: sentence.map { WordShape($0).core }).map(\.index)
        return sentenceStart + ((marked + spoken).max() ?? 0)
    }
}
