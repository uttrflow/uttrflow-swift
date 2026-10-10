// The segment slices Docs/segments.md names, each scored by the bakeoff as its own column.
import Testing
@testable import UttrflowEval

@Suite("Segment slices")
struct SegmentCorpusTests {
    @Test("every segment has at least five cases in the scored corpus")
    func everySegmentIsCovered() {
        for segment in Segment.allCases {
            #expect(EvaluationCorpus.all.count(where: { $0.segment == segment }) >= 5, "\(segment.rawValue)")
        }
    }
}
