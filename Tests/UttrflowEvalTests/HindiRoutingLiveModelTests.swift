// Runs the Hindi and Hinglish corpus through the shipping router, on whatever models this Mac has.
import UttrflowAI
import UttrflowCore
import Testing

@testable import UttrflowEval

@Suite("Hindi through the shipping router")
struct HindiRoutingLiveModelTests {
    @Test(
        "Hindi never reaches Apple's model and always comes out in Latin script",
        arguments: EvaluationCorpus.multilingual)
    func hindiSkipsApplesModel(testCase: EvaluationCase) async throws {
        let result = try await TextTransformers.router().transform(testCase.transformationRequest())
        #expect(result.producedBy != .foundationModels, "\(testCase.id) was tidied by Apple's model")
        let latin = result.text.unicodeScalars.allSatisfy { $0.isASCII }
        #expect(latin, "\(testCase.id) wrote \(result.text)")
    }
}
