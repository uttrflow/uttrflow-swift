import Testing

@testable import UttrflowAI

@Suite("Foundation model request limits")
struct FoundationModelRequestBudgetTests {
    @Test("estimates ASCII tokens and counts every non-ASCII scalar")
    func estimatesTokens() {
        #expect(FoundationModelRequestBudget.estimatedTokens(in: "four words here") == 5)
        #expect(FoundationModelRequestBudget.estimatedTokens(in: "你好世界") == 4)
    }

    @Test("accounts for instructions, prompt, schema, expected output and safety margin")
    func checksAllContextCosts() {
        #expect(
            FoundationModelRequestBudget.fits(
                contextSize: 500, instructions: 100, prompt: 100, schema: 100, expectedOutput: 136))
        #expect(
            !FoundationModelRequestBudget.fits(
                contextSize: 499, instructions: 100, prompt: 100, schema: 100, expectedOutput: 136))
        #expect(
            !FoundationModelRequestBudget.fits(
                contextSize: 1_000, instructions: 100, prompt: 300, schema: 100, expectedOutput: 500))
    }

    @Test("plans with the estimate while it fits, so no tokenizer call follows the warm")
    func estimatesPromptWhileItFits() {
        let short = "Spoken: \"I will go to the office tomorrow morning.\""
        let estimate = FoundationModelRequestBudget.estimatedTokens(in: short)
        #expect(
            FoundationModelRequestBudget.estimatedPromptTokens(
                short, contextSize: 4_096, instructions: 1_200, schema: 30) == estimate)
        #expect(
            FoundationModelRequestBudget.estimatedPromptTokens(
                short, contextSize: 1_200 + 30 + 2 * estimate + 64, instructions: 1_200, schema: 30)
                == estimate)
        #expect(
            FoundationModelRequestBudget.estimatedPromptTokens(
                short, contextSize: 1_200 + 30 + 2 * estimate + 63, instructions: 1_200, schema: 30)
                == nil)
    }

    @Test("scales with request length and caps below the engine ceiling")
    func scalesAllowance() {
        #expect(FoundationModelRequestBudget.allowance(for: 150) == .milliseconds(4_800))
        #expect(FoundationModelRequestBudget.allowance(for: 300) == .milliseconds(6_600))
        #expect(FoundationModelRequestBudget.allowance(for: 1_000) == .seconds(15))
        #expect(FoundationModelRequestBudget.allowance(for: 2_000) == .seconds(15))
    }

    @Test("bounds the answer by the guard's growth over the prompt plus the structure")
    func boundsResponse() {
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: 40, schemaTokens: 30) == 110)
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: 0, schemaTokens: 0) == 1)
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: -5, schemaTokens: 12) == 12)
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: 1, schemaTokens: .max) == .max)
    }
}
