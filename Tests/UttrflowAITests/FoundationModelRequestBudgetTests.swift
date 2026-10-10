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

    @Test("scales with request length and caps below the engine ceiling")
    func scalesAllowance() {
        #expect(FoundationModelRequestBudget.allowance(for: 150) == .milliseconds(4_800))
        #expect(FoundationModelRequestBudget.allowance(for: 300) == .milliseconds(6_600))
        #expect(FoundationModelRequestBudget.allowance(for: 1_000) == .seconds(15))
        #expect(FoundationModelRequestBudget.allowance(for: 2_000) == .seconds(15))
    }

    @Test("lengthens the allowance when the model has been measured answering slowly")
    func measuredThroughputLengthens() {
        let slow = FoundationModelRequestBudget.allowance(for: 75, timePerWord: .milliseconds(100))
        #expect(slow == .milliseconds(11_250))
        #expect(FoundationModelRequestBudget.allowance(for: 75, timePerWord: .seconds(1)) == .seconds(15))
    }

    @Test("never shortens the length-scaled allowance for a fast model")
    func measuredThroughputNeverShortens() {
        let fast = FoundationModelRequestBudget.allowance(for: 75, timePerWord: .milliseconds(1))
        #expect(fast == FoundationModelRequestBudget.allowance(for: 75))
    }

    @Test("keeps the slowest of its recent answers, counting a short piece as twenty words")
    func throughputKeepsSlowestRecent() {
        let throughput = ModelThroughput()
        #expect(throughput.timePerWord == nil)
        throughput.record(words: 5, elapsed: .seconds(2))
        #expect(throughput.timePerWord == .milliseconds(100))
        throughput.record(words: 40, elapsed: .seconds(2))
        #expect(throughput.timePerWord == .milliseconds(100))
        for _ in 0..<ModelThroughput.window { throughput.record(words: 40, elapsed: .seconds(2)) }
        #expect(throughput.timePerWord == .milliseconds(50))
    }

    @Test("bounds the answer by the guard's growth over the prompt plus the structure")
    func boundsResponse() {
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: 40, schemaTokens: 30) == 110)
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: 0, schemaTokens: 0) == 1)
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: -5, schemaTokens: 12) == 12)
        #expect(FoundationModelRequestBudget.responseCeiling(promptTokens: 1, schemaTokens: .max) == .max)
    }
}
