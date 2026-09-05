// Tests that each context case in the corpus is about context.
import UttrflowCore
import Testing

@testable import UttrflowEval

/// Checks each context case is about context: a window present, a pair disagreeing, a scorable reference.
@Suite("Context cases")
struct ContextualCorpusTests {
    private var contextual: [EvaluationCase] { EvaluationCorpus.cases(in: .contextual) }

    /// Compares on words alone, as the scorer does, so punctuation or case cannot hide a shared sentence.
    private func normalise(_ text: String) -> String {
        Scorer.tokens(text).joined(separator: " ")
    }

    /// Cases grouped by the words spoken, so a pair is found rather than tagged and cannot lose its half.
    private var pairs: [[EvaluationCase]] {
        Dictionary(grouping: contextual) { normalise($0.spoken) }
            .values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.id ?? "") < ($1.first?.id ?? "") }
    }

    @Test("gives every context case something to see")
    func everyCaseHasAContext() {
        for testCase in contextual {
            #expect(!testCase.context.isEmpty, "\(testCase.id) has no window to look at")
        }
    }

    /// Only a disagreeing pair is evidence that context moved the answer.
    @Test("builds enough pairs to prove context is what moved the answer")
    func hasEnoughPairs() {
        #expect(pairs.count >= 3, "found \(pairs.count) pairs of shared sentences")
    }

    @Test("pairs the same words with different windows and different answers")
    func pairsDifferOnlyInContext() {
        for pair in pairs {
            let ids = pair.map(\.id).joined(separator: " / ")
            #expect(pair.count == 2, "\(ids) share a sentence three ways, which is a pair gone wrong")

            let spoken = Set(pair.map { normalise($0.spoken) })
            #expect(spoken.count == 1, "\(ids) do not really share their words")

            let sameWindow = pair.indices.contains { first in
                pair.indices.contains { second in
                    second > first && pair[first].context == pair[second].context
                }
            }
            #expect(!sameWindow, "\(ids) are shown the same window")

            let answers = Set(pair.map { normalise($0.expected) })
            #expect(answers.count == pair.count, "\(ids) expect the same answer, so neither needs context")
        }
    }

    /// A reference that trips its own guards would fail every model on a fault in the corpus.
    @Test("accepts each reference answer as a perfect answer to its own case")
    func referencesAreSelfConsistent() {
        for testCase in contextual {
            let score = Scorer.score(testCase.expected, against: testCase)
            #expect(score.similarity == 1, "\(testCase.id) does not match itself")
            #expect(score.keptEverythingRequired, "\(testCase.id) lost \(score.lost)")
            #expect(score.invented.isEmpty, "\(testCase.id) breaks its own guard: \(score.invented)")
        }
    }

    /// A context case that repeats an everyday one is scored twice under two different answers.
    @Test("shares a sentence only inside a pair, never with the rest of the corpus")
    func sentencesAreNotReusedOutsidePairs() {
        for testCase in contextual {
            let sharing = EvaluationCorpus.all.filter {
                $0.id != testCase.id && normalise($0.spoken) == normalise(testCase.spoken)
            }
            #expect(
                sharing.count <= 1,
                "\(testCase.id) shares its words with \(sharing.map(\.id))")
            for other in sharing {
                #expect(
                    other.category == .contextual,
                    "\(testCase.id) repeats \(other.id), which is not a context case")
                #expect(
                    other.context != testCase.context,
                    "\(testCase.id) and \(other.id) are the same case twice, not a pair")
            }
        }
    }

    /// A guard with nothing in it would assert nothing; punctuation is fine, the scorer matches it literally.
    @Test("keeps guards to things the scorer can actually look for")
    func guardsAreNotEmpty() {
        for testCase in contextual {
            for forbidden in testCase.mustNotAdd {
                #expect(
                    forbidden.contains { !$0.isWhitespace },
                    "\(testCase.id) forbids \"\(forbidden)\", which is nothing at all")
            }
        }
    }

    /// Neither a sort direction nor a row count was spoken, so neither is allowed.
    @Test("never lets a sort direction or a row limit be inferred")
    func orderingIsNotEmbellished() {
        let ordered = contextual.filter { $0.expected.uppercased().contains("ORDER BY") }
        #expect(!ordered.isEmpty, "no case exercises the sort-direction guard")
        for testCase in ordered {
            let guards = Set(testCase.mustNotAdd.map { $0.uppercased() })
            #expect(guards.contains("DESC"), "\(testCase.id) allows DESC to be invented")
            #expect(guards.contains("DESCENDING"), "\(testCase.id) allows DESCENDING to be invented")
            #expect(guards.contains("LIMIT"), "\(testCase.id) allows a row limit to be invented")
        }
    }
}
