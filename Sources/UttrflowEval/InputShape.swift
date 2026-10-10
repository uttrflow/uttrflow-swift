// The shape of the transcript a case hands an engine: as written, or as a punctuating recogniser emits it.
import UttrflowCore

/// How a case's `spoken` text is cased and closed before an engine sees it.
public enum InputShape: String, Sendable, Equatable, CaseIterable, Codable {
    /// The transcript exactly as the case writes it.
    case bare
    /// A capital first letter and a closing mark, which is what the default recogniser emits.
    case recogniser
}

extension EvaluationCase {
    /// Marks a recogniser closes a sentence with; a case whose `expected` ends in none of them gets a full stop.
    static let closingMarks: Set<Character> = [".", "?", "!"]

    /// Whether the shape changes this case: English, one line, not grammar, lower case first and unclosed.
    public var takesRecogniserShape: Bool {
        guard language == .english, category != .grammar, !spoken.contains("\n"),
            let first = spoken.first, first.isLowercase,
            let last = spoken.last, !Self.closingMarks.contains(last)
        else { return false }
        return true
    }

    /// This case with `spoken` in the given shape; everything the case scores against stays as written.
    public func shaped(_ shape: InputShape) -> EvaluationCase {
        guard shape == .recogniser, takesRecogniserShape, let first = spoken.first else { return self }
        let mark = expected.last.flatMap { Self.closingMarks.contains($0) ? $0 : nil } ?? "."
        return EvaluationCase(
            id: id, category: category, language: language,
            spoken: first.uppercased() + spoken.dropFirst() + String(mark),
            expected: expected, mustKeep: mustKeep, context: context, mustNotAdd: mustNotAdd,
            destination: destination, mustBeginWith: mustBeginWith, mustEndWith: mustEndWith,
            minimumSentences: minimumSentences, expectedExact: expectedExact, doubtful: doubtful,
            pausedAfter: pausedAfter, dictionary: dictionary)
    }
}
