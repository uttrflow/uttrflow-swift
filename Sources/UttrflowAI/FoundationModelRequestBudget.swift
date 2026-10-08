import UttrflowCore

/// Conservative limits for one request to Apple's on-device model.
enum FoundationModelRequestBudget {
    /// Allow room for metadata not represented by the visible prompt and response estimates.
    static let contextSafetyTokens = 64

    /// Estimates ASCII at three characters per token and counts every non-ASCII scalar separately.
    static func estimatedTokens(in text: String) -> Int {
        var tokens = 0
        var asciiScalars = 0
        for scalar in text.unicodeScalars {
            if scalar.value < 128 {
                asciiScalars += 1
            } else {
                tokens += (asciiScalars + 2) / 3 + 1
                asciiScalars = 0
            }
        }
        return tokens + (asciiScalars + 2) / 3
    }

    /// Requires room for instructions, the actual prompt, its schema, and a response as long as the input.
    static func fits(
        contextSize: Int, instructions: Int, prompt: Int, schema: Int, expectedOutput: Int
    ) -> Bool {
        guard contextSize > 0, instructions >= 0, prompt >= 0, schema >= 0, expectedOutput >= 0 else {
            return false
        }
        let total = instructions.addingReportingOverflow(prompt)
        guard !total.overflow else { return false }
        let withSchema = total.partialValue.addingReportingOverflow(schema)
        guard !withSchema.overflow else { return false }
        let withOutput = withSchema.partialValue.addingReportingOverflow(expectedOutput)
        guard !withOutput.overflow else { return false }
        let withMargin = withOutput.partialValue.addingReportingOverflow(contextSafetyTokens)
        return !withMargin.overflow && withMargin.partialValue <= contextSize
    }

    /// The most tokens a tidy answer may generate: the guard's growth allowance over the prompt, plus the structure.
    static func responseCeiling(promptTokens: Int, schemaTokens: Int) -> Int {
        let growth = Double(max(0, promptTokens)) * MeaningPreservationGuard.maximumGrowthFactor
        let ceiling = Int(growth.rounded(.up)).addingReportingOverflow(max(0, schemaTokens))
        return ceiling.overflow ? Int.max : max(1, ceiling.partialValue)
    }

    /// Longer prompts receive more time, with a short baseline and a cap below the router's 20-second ceiling.
    static func allowance(for wordCount: Int) -> Duration {
        let milliseconds = min(15_000, max(4_000, 3_000 + max(0, wordCount) * 12))
        return .milliseconds(Int64(milliseconds))
    }
}
