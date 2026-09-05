// Word error rate: an edit distance over words, kept in Core so the app never links the evaluation harness.

/// How far a transcript is from what was read: edits over reference words (`Docs/core-word-error-rate.md`).
public struct WordErrorRate: Sendable, Equatable, Codable {
    /// One step of the alignment; kept, not only counted, because the alignment says which words went wrong.
    public enum Operation: Sendable, Equatable, Codable {
        /// A reference word the transcript reproduced.
        case match(String)
        /// A reference word the transcript replaced with another.
        case substitution(reference: String, hypothesis: String)
        /// A reference word the transcript never produced.
        case deletion(String)
        /// A transcript word with nothing in the reference behind it.
        case insertion(String)

        /// Which of the four an operation is, without its words; the grouping the counts and report share.
        public enum Kind: String, Sendable, Equatable, CaseIterable, Codable {
            case match
            case substitution
            case deletion
            case insertion
        }

        /// This operation's kind.
        public var kind: Kind {
            switch self {
            case .match: .match
            case .substitution: .substitution
            case .deletion: .deletion
            case .insertion: .insertion
            }
        }
    }

    /// The edits, in reference order.
    public let alignment: [Operation]

    /// A rate over an alignment already computed.
    public init(alignment: [Operation]) {
        self.alignment = alignment
    }

    /// How many operations are of `kind`.
    public func count(of kind: Operation.Kind) -> Int {
        alignment.count { $0.kind == kind }
    }

    public var hits: Int { count(of: .match) }

    public var substitutions: Int { count(of: .substitution) }

    public var deletions: Int { count(of: .deletion) }

    public var insertions: Int { count(of: .insertion) }

    /// Every operation that is not a match.
    public var errors: Int { alignment.count { $0.kind != .match } }

    /// The denominator: every word that was read aloud.
    public var referenceWordCount: Int { hits + substitutions + deletions }

    /// Errors over reference words, or `nil` when nothing was read; a zero here would flatter.
    public var rate: Double? {
        guard referenceWordCount > 0 else { return nil }
        return Double(errors) / Double(referenceWordCount)
    }

    /// Levenshtein over words with unit costs, backtraced diagonal first so a tie splits the same way always.
    public static func measure(reference: [String], hypothesis: [String]) -> WordErrorRate {
        let rows = reference.count + 1
        let columns = hypothesis.count + 1
        var cost = [Int](repeating: 0, count: rows * columns)
        func index(_ row: Int, _ column: Int) -> Int { row * columns + column }

        for row in 1..<rows { cost[index(row, 0)] = row }
        for column in 1..<columns { cost[index(0, column)] = column }
        for row in 1..<rows {
            for column in 1..<columns {
                let matched = reference[row - 1] == hypothesis[column - 1]
                cost[index(row, column)] = Swift.min(
                    cost[index(row - 1, column - 1)] + (matched ? 0 : 1),
                    cost[index(row - 1, column)] + 1,
                    cost[index(row, column - 1)] + 1
                )
            }
        }

        var alignment: [Operation] = []
        var row = reference.count
        var column = hypothesis.count
        while row > 0 || column > 0 {
            let here = cost[index(row, column)]
            if row > 0, column > 0 {
                let matched = reference[row - 1] == hypothesis[column - 1]
                if here == cost[index(row - 1, column - 1)] + (matched ? 0 : 1) {
                    alignment.append(
                        matched
                            ? .match(reference[row - 1])
                            : .substitution(
                                reference: reference[row - 1], hypothesis: hypothesis[column - 1]))
                    row -= 1
                    column -= 1
                    continue
                }
            }
            if row > 0, here == cost[index(row - 1, column)] + 1 {
                alignment.append(.deletion(reference[row - 1]))
                row -= 1
                continue
            }
            alignment.append(.insertion(hypothesis[column - 1]))
            column -= 1
        }

        return WordErrorRate(alignment: alignment.reversed())
    }

    /// One corpus rate: errors and reference words summed before dividing; a short passage cannot swing it.
    public static func combined(_ rates: [WordErrorRate]) -> WordErrorRate {
        WordErrorRate(alignment: rates.flatMap(\.alignment))
    }
}
