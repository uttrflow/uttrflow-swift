import Testing

@testable import UttrflowLocalModel

@Suite("Local cleanup token budget")
struct CleanupTokenBudgetTests {
    @Test("an empty prompt still has room for a short cleanup reply")
    func emptyPromptBudget() {
        #expect(MLXCandidateScorer.tidyBudget(for: "") == 32)
    }

    @Test("the reply allowance counts prompt bytes rather than characters")
    func multibytePromptBudget() {
        #expect(MLXCandidateScorer.tidyBudget(for: "éé") == 34)
        #expect(MLXCandidateScorer.tidyBudget(for: "abcd") == 34)
    }

    @Test("long prompts cannot raise the cleanup reply beyond its token cap")
    func longPromptBudget() {
        #expect(MLXCandidateScorer.tidyBudget(for: String(repeating: "x", count: 1_000)) == 256)
        #expect(MLXCandidateScorer.tidyBudget(for: String(repeating: "é", count: 1_000)) == 256)
    }
}
