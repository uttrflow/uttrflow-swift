public import UttrflowPredict
import UttrflowAI
import FoundationModels

/// Apple's on-device model asked the same question as the local one, so the two can be held to the same catalogue; it answers in text only, so nothing here can write the line into its turn or hold its first tokens to the typed word.
@available(macOS 26, *)
public actor AppleCandidateGenerator: PassShowing {
    /// The shape the model fills in, since a structured answer is what keeps it from opening with a comment.
    @Generable
    struct Continuation {
        @Guide(
            description: "The given text repeated and then continued into one complete line. Never a comment."
        )
        var line: String
    }

    public init() {}

    public var isReady: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        try await pass(for: typed, in: situation)?.completions ?? []
    }

    /// The one-line pass as the model wrote it into the structured answer, beside what the parser made of it.
    public func pass(for typed: String, in situation: GenerationSituation) async throws -> GenerationPass? {
        guard CompletionPromptBuilder.choiceValuesIfPassAllowed(situation.choices, asking: .one) != nil else {
            return nil
        }
        let promptTyped = PromptText.promptValue(typed)
        guard promptTyped == typed,
            typed.trimmingCharacters(in: .whitespaces).count >= MLXCandidateScorer.minimumTypedLength
        else {
            return nil
        }
        let register = Register.infer(from: situation, typed: typed)
        let message = CompletionPromptBuilder.message(
            typed: promptTyped, in: situation, register: register, asking: .one)
        // A fresh session per pass, as the local model's warm prefix gives it: no earlier line bleeds into this one.
        let session = LanguageModelSession(instructions: MLXCandidateScorer.instructions)
        let options = GenerationOptions(temperature: 0, maximumResponseTokens: register.maxTokens * 2)
        let response = try await session.respond(to: message, generating: Continuation.self, options: options)
        let answer = response.content.line
        let completions = CompletionText.modelCompletions(
            from: answer, typed: typed, echoPolicy: .joinAtBoundary, in: situation)
        return GenerationPass(text: response.content.line, stopReason: "structured", completions: completions)
    }
}
