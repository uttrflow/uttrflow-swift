// Tests leave-one-speaker-out coverage of a term's wrong forms by the other speakers' wrong forms.
import Testing
import UttrflowEval

@Suite("SyntheticPathCoverage")
struct SyntheticPathCoverageTests {
    private func read(_ term: String, as heard: String, by speaker: String) -> HarvestUtterance {
        HarvestUtterance(
            reference: term.split(separator: " ").map(String.init),
            recognised: heard.split(separator: " ").map(String.init), group: "en", speaker: speaker)
    }

    @Test func aWrongFormIsCoveredOnlyWhenAnotherSpeakerProducedIt() {
        let coverage = SyntheticPathCoverage([
            read("zorbex", as: "zor bex", by: "a"),
            read("zorbex", as: "zor bex", by: "b"),
            read("zorbex", as: "sorbex", by: "c"),
            read("quillan", as: "quillan", by: "a"),
            read("quillan", as: "quill and", by: "b"),
            read("quillan", as: "quill and", by: "b"),
        ])
        #expect(coverage.covered == Proportion(hits: 2, of: 5))
        #expect(coverage.pathsPerTerm == 1.5)
        #expect(coverage.termsAlwaysRight == 0)
    }

    @Test func termsHeardRightAddNoTrials() {
        let coverage = SyntheticPathCoverage([read("velmora", as: "velmora", by: "a")])
        #expect(coverage.covered.total == 0)
        #expect(coverage.covered.value == nil)
        #expect(coverage.termsAlwaysRight == 1)
        #expect(coverage.pathsPerTerm == 0)
    }
}
