import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowEval

/// Holds every corpus case's passes to their grants, so the guard's wider baseline changes a verdict only where a pass overreached.
@Suite("The corpus against each pass's grant")
struct RemovalGrantCorpusTests {
    /// The cases where a pass removes a word it has no grant for, and what it removes.
    static let overreaching: [String: [UnauthorisedRemoval]] = [
        "acronym-spelled-like-a-filler": [UnauthorisedRemoval(pass: .fillers, text: "ER")],
        "answer-no-before-a-restated-phrase": [UnauthorisedRemoval(pass: .selfCorrection, text: "no,")],
    ]

    @Test(
        "finds a removal beyond its grant only in the cases that record one", arguments: EvaluationCorpus.all)
    func removalsStayWithinGrants(testCase: EvaluationCase) {
        let request = testCase.transformationRequest()
        let pipeline = CleaningPipeline.beforeModel(
            for: .standard(for: request.situation.destination), situation: request.situation)
        let draft = pipeline.run(Draft(transcription: request.transcription))
        #expect(
            RemovalAudit.unauthorised(in: draft, grants: pipeline.grants) == Self.overreaching[testCase.id]
                ?? [])
    }

    @Test("names only cases the corpus holds")
    func namesRealCases() {
        #expect(Set(Self.overreaching.keys).isSubset(of: Set(EvaluationCorpus.all.map(\.id))))
    }
}
