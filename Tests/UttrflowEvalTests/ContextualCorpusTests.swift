import UttrflowCore
import Testing

@testable import UttrflowEval

/// What the context half of the corpus has to be true of before it can measure
/// anything.
///
/// A context case is easy to write badly: give it a window, write down the answer you
/// hoped for, and never notice that plain dictation would have produced the same
/// sentence. These tests are the checks that a case is actually about context — that
/// a window is present, that a pair of windows disagrees, and that the reference is
/// one the scorer itself accepts.
@Suite("Context cases")
struct ContextualCorpusTests {
    private var contextual: [EvaluationCase] { EvaluationCorpus.cases(in: .contextual) }

    /// Compares on words alone, the way the scorer does, so punctuation or case cannot
    /// hide two cases sharing a sentence.
    private func normalise(_ text: String) -> String {
        Scorer.tokens(text).joined(separator: " ")
    }

    /// Cases grouped by the words spoken. A pair is whatever more than one window
    /// heard the same sentence, so nothing has to be tagged by hand and a pair cannot
    /// quietly lose its other half.
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

    /// One case cannot show that context did anything: if the answer looks right, the
    /// context may have been ignored and plain dictation may have said the same. Only
    /// a disagreeing pair is evidence.
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

    /// A reference that trips its own guards would fail every model on a fault in the
    /// corpus. Both directions matter here: the words that must survive, and the words
    /// the window must not talk the model into adding.
    @Test("accepts each reference answer as a perfect answer to its own case")
    func referencesAreSelfConsistent() {
        for testCase in contextual {
            let score = Scorer.score(testCase.expected, against: testCase)
            #expect(score.similarity == 1, "\(testCase.id) does not match itself")
            #expect(score.keptEverythingRequired, "\(testCase.id) lost \(score.lost)")
            #expect(score.invented.isEmpty, "\(testCase.id) breaks its own guard: \(score.invented)")
        }
    }

    /// Shared sentences are the point of a pair and a bug anywhere else: a context
    /// case that repeats an everyday one is scored twice under two different answers.
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

    /// A guard with nothing in it cannot be looked for, and would quietly assert
    /// nothing. Punctuation is fine — the scorer searches for it literally — so the
    /// rule is only that a guard must hold something.
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

    /// The one inference a SQL window invites most: an ordering was asked for, so a
    /// direction gets chosen, and a row count nobody mentioned gets tacked on. Neither
    /// was spoken, so neither is allowed.
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
