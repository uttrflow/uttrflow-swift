/// How far a transcript is from what was actually read.
///
/// A genuine edit distance over words, not the word overlap ``Scorer`` uses. The two
/// measure different things and both are needed: a rewrite may say the same thing in
/// other words and still be right, so clean-up is scored on similarity; a transcript
/// that says other words is wrong by definition, so a recogniser is scored on the
/// number of edits it takes to repair it.
///
/// `WER = (substitutions + deletions + insertions) / reference words`, which can exceed
/// 1 — a recogniser that hallucinates a paragraph over a two-word utterance is more than
/// 100% wrong, and clamping that to 1 would hide it.

// Here rather than in UttrflowEval, which is where it was written and where most of its
// callers still are.
//
// The evaluation harness must never be linked into the shipped app — it knows how to
// reach a private bucket of real people's recordings, and Scripts/bundle.sh now refuses a
// build whose binary carries its symbols. But onboarding's microphone check needs to score
// a read passage, which is the same edit distance. Lifting the algorithm into Core lets
// both have it without the app importing the harness, and without a second implementation
// of a measurement two parts of the product must agree on.

public struct WordErrorRate: Sendable, Equatable, Codable {
    /// One step of the alignment between reference and transcript.
    ///
    /// Kept, rather than only the counts, because a rate says a passage went badly and
    /// only the alignment says which words — and the fix is nearly always in the corpus
    /// or the normalisation rather than the recogniser.
    public enum Operation: Sendable, Equatable, Codable {
        case match(String)
        case substitution(reference: String, hypothesis: String)
        /// A reference word the transcript never produced.
        case deletion(String)
        /// A transcript word with nothing in the reference behind it.
        case insertion(String)

        /// Which of the four an operation is, without its words.
        ///
        /// The counts and the report both need to group by kind, and asking each of them
        /// to write out its own `case` test is how two of them end up disagreeing.
        public enum Kind: String, Sendable, Equatable, CaseIterable, Codable {
            case match
            case substitution
            case deletion
            case insertion
        }

        public var kind: Kind {
            switch self {
            case .match: .match
            case .substitution: .substitution
            case .deletion: .deletion
            case .insertion: .insertion
            }
        }
    }

    public let alignment: [Operation]

    public init(alignment: [Operation]) {
        self.alignment = alignment
    }

    public func count(of kind: Operation.Kind) -> Int {
        alignment.count { $0.kind == kind }
    }

    public var hits: Int { count(of: .match) }

    public var substitutions: Int { count(of: .substitution) }

    public var deletions: Int { count(of: .deletion) }

    public var insertions: Int { count(of: .insertion) }

    public var errors: Int { alignment.count { $0.kind != .match } }

    /// The denominator: every word that was read aloud.
    public var referenceWordCount: Int { hits + substitutions + deletions }

    /// `nil` when nothing was read, because a rate with no denominator is not a rate.
    ///
    /// Reported as absent rather than as zero: an empty reference means the harness has
    /// nothing to say, and saying "0% error" instead would be a lie in the flattering
    /// direction.
    public var rate: Double? {
        guard referenceWordCount > 0 else { return nil }
        return Double(errors) / Double(referenceWordCount)
    }

    /// Aligns two word sequences and counts the edits between them.
    ///
    /// Ordinary Levenshtein over words with unit costs, then a backtrace to attribute
    /// each edit. The backtrace prefers a diagonal step, then a deletion, then an
    /// insertion. The tie-break cannot change the total — every optimal path has the
    /// same number of edits — but it does decide how a tie is split between the three
    /// kinds, and a split that varied run to run would make the report unreadable.
    ///
    /// "Send it to Priya" heard as "send to preeya now" is three edits either way: a
    /// deletion, a substitution and an insertion, or three substitutions. This reports
    /// the second. The rate is the same; only the breakdown differs, so the breakdown is
    /// read as "three words wrong here", never as evidence about which kind of mistake
    /// the recogniser is prone to.
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

    /// One rate over several passages.
    ///
    /// Errors and reference words are summed before dividing — the standard corpus WER —
    /// rather than averaging the per-passage rates. Averaging rates would give a
    /// six-word passage the same weight as a sixty-word one, so a single stumble over a
    /// short sentence could swing the headline figure by more than a whole bad passage.
    public static func combined(_ rates: [WordErrorRate]) -> WordErrorRate {
        WordErrorRate(alignment: rates.flatMap(\.alignment))
    }
}
