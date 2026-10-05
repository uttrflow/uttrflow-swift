// Guards the request-shaped dictation corpus: every class measured, every case able to catch a model that obeys.
import Testing

@testable import UttrflowEval

@Suite("Request-shaped dictation")
struct RequestMatrixTests {
    private var cases: [RequestCase] { EvaluationCorpus.requestCases }

    @Test("measures every class with at least the floor of cases")
    func everyClassMeasured() {
        let matrix = RequestMatrix()
        #expect(matrix.underMeasured.isEmpty, "under the floor: \(matrix.underMeasured)")
        #expect(RequestMatrix(cases: []).underMeasured == RequestClass.allCases)
    }

    @Test("names every way a model fails a request")
    func everyFailureRepresented() {
        #expect(Set(cases.map(\.failure)) == Set(RequestFailure.allCases))
    }

    @Test("holds every request case in the not-a-request category, once")
    func casesAreTheCategory() {
        let ids = cases.map(\.evaluation.id)
        #expect(Set(ids).count == ids.count)
        #expect(EvaluationCorpus.cases(in: .notARequest).map(\.id).filter(Set(ids).contains) == ids)
    }

    /// A reference that trips its own guards would fail every model on a fault in the corpus.
    @Test("accepts each expected text as a perfect answer to its own case")
    func referencesPass() {
        for request in cases {
            let score = Scorer.score(request.evaluation.expected, against: request.evaluation)
            #expect(score.passed && score.isExact, "\(request.evaluation.id) fails itself: \(score)")
        }
    }

    /// Failing on similarity alone would leave the failure unnamed; a guard has to catch it.
    @Test("fails a model that takes the dictation as a request, by a named guard")
    func requestOutputFails() {
        for request in cases {
            let score = Scorer.score(request.failed, against: request.evaluation)
            #expect(!score.passed, "\(request.evaluation.id) passes the \(request.failure) output")
            #expect(
                !score.invented.isEmpty || !score.lost.isEmpty,
                "\(request.evaluation.id) catches the \(request.failure) output by similarity alone")
        }
    }
}
