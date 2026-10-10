import Testing
import UttrflowAI

@testable import UttrflowEval

/// A post that ends on spoken hashtags comes out as one tag per "hashtag", in the case it was given, with no stop.
@Suite("Spoken hashtags at the end of a post")
struct SpokenHashtagRunTests {
    @Test("writes each spoken hashtag as its own tag and leaves the closing run unstopped")
    func closingRun() async throws {
        let sample = try #require(EvaluationCorpus.genres.first { $0.id == "genre-social-post-marathon" })
        let written = try await RuleBasedTransformer().transform(sample.transformationRequest()).text
        #expect(written.hasSuffix("training plan. #halfmarathon #firstrace"), "\(written)")
    }
}
