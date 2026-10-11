import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

@Suite("Protocol references use the registered name")
struct ProtocolReferenceTests {
    @Test("the contextual protocol reference keeps its registered mixed name")
    func canonicalProtocolReferenceIsAccepted() async throws {
        let sample = try #require(EvaluationCorpus.all.first { $0.id == "probe-protocol-names" })
        let term = try #require(TechnicalLexicon.terms.first { $0.id == "OAuth2" })
        #expect(sample.expected.contains(term.id))
        let verdict = await MeaningPreservationGuard().verdict(
            onReference: sample.expected, for: sample.transformationRequest())
        #expect(verdict == .accepted)
    }

    @Test("an altered or dropped registered identifier is refused", arguments: ["OAuth3", "OAuth"])
    func alteredProtocolIdentifierIsRefused(identifier: String) async throws {
        let sample = try #require(EvaluationCorpus.all.first { $0.id == "probe-protocol-names" })
        let canonical = sample.expected.replacingOccurrences(of: "OAuth 2", with: "OAuth2")
        let rewritten = canonical.replacingOccurrences(of: "OAuth2", with: identifier)
        let verdict = await MeaningPreservationGuard().verdict(
            onReference: rewritten, for: sample.transformationRequest())
        #expect(!verdict.isAccepted)
    }
}
