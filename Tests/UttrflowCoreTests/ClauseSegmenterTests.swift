import Testing
import UttrflowCore

@Suite("Clause segmenter")
struct ClauseSegmenterTests {
    private func starts(_ text: String, pauses: [Double?] = []) -> [ClauseSegmenter.Boundary] {
        ClauseSegmenter.boundaries(in: text.split(separator: " ").map(String.init), pauses: pauses)
    }

    @Test(
        "an opening interjection or sentence adverb stands apart from its clause",
        arguments: [
            "well i think we should go now", "so we left early", "however the meeting moved to friday",
            "yes that works for me", "okay let us start", "actually the plan changed",
        ])
    func opener(text: String) {
        #expect(starts(text).first == .init(index: 1, evidence: .afterOpener))
    }

    @Test("a conjunction between two clauses with their own subjects starts a clause")
    func coordinated() {
        let joined = ClauseSegmenter.Boundary(index: 3, evidence: .coordinatedClause)
        #expect(starts("i called him but he did not answer") == [joined])
        #expect(starts("we left early and then it rained") == [joined])
    }

    @Test(
        "a conjunction joining words or a shared subject starts no clause",
        arguments: ["we need eggs milk and bread", "i went home and slept", "the ship sails today"])
    func noClause(text: String) {
        #expect(starts(text).isEmpty)
    }

    @Test("a long enough pause starts a clause where the words show none")
    func pause() {
        let text = "i went home and slept"
        #expect(starts(text, pauses: [nil, nil, 0.6, nil]) == [.init(index: 3, evidence: .pause)])
        #expect(starts(text, pauses: [nil, nil, 0.1, nil]).isEmpty)
    }

    @Test("word evidence wins over a pause at the same word")
    func lexicalFirst() {
        let found = starts("i called him but he did not answer", pauses: [nil, nil, 0.9])
        #expect(found == [.init(index: 3, evidence: .coordinatedClause)])
    }

    @Test("no words, no clauses")
    func empty() {
        #expect(ClauseSegmenter.boundaries(in: []).isEmpty)
        #expect(ClauseSegmenter.boundaries(in: ["hello"]).isEmpty)
    }
}
