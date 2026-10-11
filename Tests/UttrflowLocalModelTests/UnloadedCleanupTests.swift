import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowLocalModel

@Suite("Cleanup before local weights are loaded")
struct UnloadedCleanupTests {
    private func scorer() -> MLXCandidateScorer {
        MLXCandidateScorer(
            model: .gemma3, maximumTokens: 16,
            bufferCache: BufferCacheControl(hold: {}, clear: {}))
    }

    @Test("an unloaded scorer reports not loaded before checking the requested language")
    func unavailableBeforeLoading() async {
        let scorer = scorer()
        for language in [LanguageCode?.none, .english, .hindi] {
            #expect(
                await scorer.availability(for: language)
                    == .unavailable(reason: .other("the local model is not loaded")))
        }
        #expect(!(await scorer.isReady))
    }

    @Test("instruction cleanup reports not ready without loading weights")
    func instructionsRefuseBeforeLoading() async {
        let scorer = scorer()
        await #expect(throws: TransformationError.transformFailed(kind: .localModel, failure: .notReady)) {
            try await scorer.rewrite(
                "synthetic sample", instructions: "Preserve the words.", kind: .localModel)
        }
        #expect(!(await scorer.isReady))
    }

    @Test("chat-prompt cleanup reports not ready without loading weights")
    func promptRefusesBeforeLoading() async {
        let scorer = scorer()
        let prompt = ModelPrompt(rules: "Preserve the words.", examples: [])
        await #expect(throws: TransformationError.transformFailed(kind: .localModel, failure: .notReady)) {
            try await scorer.rewrite("synthetic sample", prompt: prompt, kind: .localModel)
        }
        #expect(!(await scorer.isReady))
    }
}
