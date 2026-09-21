import Testing

@testable import UttrflowLocalModel

/// Where the model's judgement of a candidate starts, decided without loading a model.
@Suite("Candidate scoring span")
struct CandidateScorerSpanTests {
    @Test("The typed opening is taken from the candidate itself, so the two tokenise the same way.")
    func typedPartComesFromTheCandidate() {
        #expect(CompletionText.typedPart(of: "ls -l", following: "ls") == "ls")
        #expect(CompletionText.typedPart(of: "ls -l", following: "ls ") == "ls ")
        #expect(CompletionText.typedPart(of: "git checkout main", following: "git c") == "git c")
    }

    @Test("A candidate matched without regard to case keeps its own spelling of the typed part.")
    func typedPartKeepsTheCandidatesCase() {
        #expect(CompletionText.typedPart(of: "Git status", following: "git s") == "Git s")
    }

    @Test("A candidate that does not carry what was typed is judged whole, with nothing taken as typed.")
    func fuzzyCandidateHasNoTypedPart() {
        #expect(CompletionText.typedPart(of: "git status", following: "gti s").isEmpty)
        #expect(CompletionText.typedPart(of: "ls", following: "ls -l").isEmpty)
    }

    @Test("Nothing typed means nothing of the candidate is skipped.")
    func emptyContextHasNoTypedPart() {
        #expect(CompletionText.typedPart(of: "ls -l", following: "").isEmpty)
    }

    @Test("Scoring starts after the tokens the typed opening shares with the whole line.")
    func startsAfterTheSharedTokens() {
        #expect(ScoredSpan(whole: [2, 10, 11, 12], typed: [2, 10], bytes: [])?.start == 2)
    }

    @Test("A join that retokenises is scored from where the streams diverge, not from where the text ends.")
    func retokenisedJoinStartsAtTheDivergence() {
        #expect(ScoredSpan(whole: [2, 10, 30, 12], typed: [2, 10, 11], bytes: [])?.start == 2)
    }

    @Test("The first token is never scored, since nothing predicts it.")
    func firstTokenIsNeverScored() {
        #expect(ScoredSpan(whole: [10, 11], typed: [], bytes: [])?.start == 1)
        #expect(ScoredSpan(whole: [10, 11], typed: [99], bytes: [])?.start == 1)
    }

    @Test("A candidate with nothing past what was typed has nothing to be judged on.")
    func nothingLeftToScore() {
        #expect(ScoredSpan(whole: [2, 10], typed: [2, 10], bytes: [])?.start == nil)
        #expect(ScoredSpan(whole: [2, 10], typed: [2, 10, 11], bytes: [])?.start == nil)
        #expect(ScoredSpan(whole: [10], typed: [], bytes: [])?.start == nil)
        #expect(ScoredSpan(whole: [], typed: [], bytes: [])?.start == nil)
    }
}
