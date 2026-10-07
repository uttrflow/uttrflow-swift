// Plans "replace X with Y" against the last insertion: X is found as a word sequence by `WordForms`, never by shape.
import UttrflowCore

/// The words to find and the words to write, read from an utterance said under the editing key.
public struct ReplaceRequest: Sendable, Equatable {
    /// The words to find, as spoken.
    public let find: String
    /// The words written in their place, as spoken, without the closing mark a recogniser adds.
    public let replacement: String

    public init(find: String, replacement: String) {
        self.find = find
        self.replacement = replacement
    }
}

/// What a replace does to the text of the last insertion.
public enum ReplaceOutcome: Sendable, Equatable {
    /// The new text, and how many places matched; with more than one, the match nearest the end was replaced.
    case replaced(text: String, matches: Int)
    /// No word sequence in the insertion is the one asked for, so nothing is edited.
    case notFound

    /// The new text, or `nil` when nothing matched.
    public var text: String? {
        if case .replaced(let text, _) = self { text } else { nil }
    }
}

/// Reads and applies the `replace` rows of the spoken-command registry.
public enum ReplaceCommand {
    /// The request an utterance makes, or `nil` when it does not say a replace row with words on both sides of `until`.
    public static func request(from utterance: String) -> ReplaceRequest? {
        let tokens = utterance.split(whereSeparator: \.isWhitespace).map(String.init)
        let keys = tokens.map { WordShape($0).key }
        for row in SpokenCommands.replacements where !row.until.isEmpty {
            guard keys.starts(with: row.words) else { continue }
            let findStart = row.words.count
            guard let split = firstIndex(of: row.until, in: keys, after: findStart) else { continue }
            let rest = tokens[(split + row.until.count)...]
            guard !rest.isEmpty else { continue }
            let replacement = rest.joined(separator: " ").trimmingTrailing(".,;:!?")
            guard !replacement.isEmpty else { continue }
            return ReplaceRequest(
                find: tokens[findStart..<split].joined(separator: " "), replacement: replacement)
        }
        return nil
    }

    /// `text` with the match of `request.find` nearest its end replaced by `request.replacement`.
    public static func apply(_ request: ReplaceRequest, to text: String) -> ReplaceOutcome {
        let wanted = WordShape.words(request.find)
        let words = wordRanges(in: text)
        guard !wanted.isEmpty, wanted.count <= words.count else { return .notFound }
        let starts = (0...(words.count - wanted.count)).filter { start in
            wanted.indices.allSatisfy { offset in
                WordForms.sameForm(
                    String(text[words[start + offset]]), wanted[offset], allowingRegularInflections: false)
            }
        }
        guard let start = starts.last else { return .notFound }
        let span = words[start].lowerBound..<words[start + wanted.count - 1].upperBound
        let written =
            startsSentence(at: span.lowerBound, in: text) && text[span].first?.isUppercase == true
            ? WordShape.capitalised(request.replacement) : request.replacement
        return .replaced(text: text.replacingCharacters(in: span, with: written), matches: starts.count)
    }

    /// Each run of letters and digits in `text`, the unit `WordShape.words` counts in.
    static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            let inWord = text[index].isLetter || text[index].isNumber
            if inWord, start == nil { start = index }
            if !inWord, let open = start {
                ranges.append(open..<index)
                start = nil
            }
        }
        if let open = start { ranges.append(open..<text.endIndex) }
        return ranges
    }

    /// Whether only spaces, or a sentence-closing mark before them, stand between `index` and the previous word.
    private static func startsSentence(at index: String.Index, in text: String) -> Bool {
        let before = text[..<index].reversed().drop { $0.isWhitespace || "\"'([".contains($0) }
        guard let mark = before.first else { return true }
        return ".!?".contains(mark)
    }

    private static func firstIndex(of phrase: [String], in keys: [String], after start: Int) -> Int? {
        guard keys.count >= start + phrase.count + 1 else { return nil }
        return ((start + 1)...(keys.count - phrase.count)).first {
            Array(keys[$0..<$0 + phrase.count]) == phrase
        }
    }
}

extension String {
    fileprivate func trimmingTrailing(_ marks: String) -> String {
        var text = self
        while let last = text.last, marks.contains(last) { text.removeLast() }
        return text
    }
}
