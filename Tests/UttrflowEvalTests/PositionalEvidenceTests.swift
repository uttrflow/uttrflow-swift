import Testing

@testable import UttrflowEval

/// Holds the corpus to naming each doubtful run somewhere the same spelling stands twice, so a check that reads the whole text cannot score as well as one that reads the run's own place.
@Suite("Evidence the corpus must hold for position")
struct PositionalEvidenceTests {
    /// Runs no corpus case says twice; a run may leave this list, and a new run may never join it.
    static let owedADistractorCase: Set<String> = [
        "payment sheet", "order totals", "fetch invoices", "cash", "reader",
    ]

    /// The words of a text, bared of case and edge punctuation, which is how a run is matched against it.
    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { EvaluationCase.bare(String($0)) }
    }

    /// How many times a run's words stand in that order and next to each other.
    private static func occurrences(of run: [String], in text: String) -> Int {
        let words = words(text)
        guard !run.isEmpty, words.count >= run.count else { return 0 }
        return (0...(words.count - run.count)).count { Array(words[$0..<$0 + run.count]) == run }
    }

    /// Whether some case names this run in a sentence that says it more than once.
    private static func hasADistractor(_ run: String) -> Bool {
        let wanted = words(run)
        return EvaluationCorpus.all.contains { testCase in
            testCase.doubtful.contains { words($0) == wanted }
                && occurrences(of: wanted, in: testCase.spoken) > 1
        }
    }

    /// Every distinct run the corpus doubts, which is the set this rule ratchets over.
    private static var doubtedRuns: Set<String> {
        Set(EvaluationCorpus.all.flatMap(\.doubtful).map { words($0).joined(separator: " ") })
    }

    @Test("says every doubtful run twice in some case, or records in one place that it does not")
    func everyDoubtfulRunIsMeasuredAgainstADistractor() {
        for run in Self.doubtedRuns.sorted() {
            let owed = Self.owedADistractorCase.contains(run)
            #expect(
                Self.hasADistractor(run) == !owed,
                owed
                    ? "\"\(run)\" is said twice by a case now: take it out of owedADistractorCase"
                    : "\"\(run)\" only ever stands once in the corpus: add a case that says it twice")
        }
    }

    /// A run that left the corpus entirely would otherwise sit in the list forever, unmeasured and unnoticed.
    @Test("owes a distractor case only for runs the corpus still doubts")
    func theOwedListNamesNothingStale() {
        #expect(Self.owedADistractorCase.subtracting(Self.doubtedRuns).isEmpty)
    }
}
