import Testing

@testable import UttrflowCore

/// The words of `text`, and the positions of the ones still in it, as every caller hands them over.
private func reading(_ text: String) -> (draft: Draft, live: [Int]) {
    let draft = Draft(text: text)
    return (draft, draft.presentIndices)
}

@Suite("Restatement, shared by the pass and the joiner")
struct RestatementTests {
    @Test("a trigger is one phrase, and two of them run together are one run")
    func triggerRuns() {
        let (draft, live) = reading("at four no sorry i mean at six")
        #expect(Restatement.triggerRun(at: 2, in: live, of: draft) == 4)
        #expect(Restatement.triggerRun(at: 0, in: live, of: draft) == 0)
    }

    /// "Wait" is a verb far more often than a correction, so it needs "no" or "sorry" beside it.
    @Test("wait alone is not a trigger, and wait beside no or sorry is")
    func waitNeedsCompany() {
        let alone = reading("wait a moment")
        #expect(Restatement.triggerRun(at: 0, in: alone.live, of: alone.draft) == 0)
        let paired = reading("no wait at five")
        #expect(Restatement.triggerRun(at: 0, in: paired.live, of: paired.draft) == 2)
        let sorry = reading("wait sorry at five")
        #expect(Restatement.triggerRun(at: 0, in: sorry.live, of: sorry.draft) == 2)
    }

    @Test("the half taken back has to hold a word the speaker meant, not function words alone")
    func discardedHalfHoldsContent() {
        let good = reading("at four no sorry at five")
        #expect(Restatement.discardedStart(before: 2, after: 4, in: good.live, of: good.draft) == 0)
        let bare = reading("we need to no sorry to finish")
        #expect(Restatement.discardedStart(before: 3, after: 5, in: bare.live, of: bare.draft) == nil)
    }
}

@Suite("Function words")
struct FunctionWordsTests {
    @Test("the small words carry structure, and everything else is what was said")
    func contentAndStructure() {
        #expect(FunctionWords.holds("The") && FunctionWords.holds("of") && FunctionWords.holds("had"))
        #expect(FunctionWords.isContent("coffee") && FunctionWords.isContent("four"))
        #expect(!FunctionWords.isContent("") && !FunctionWords.isContent("the"))
    }

    @Test("a curly apostrophe reads as the straight one the set is keyed by")
    func apostrophes() {
        #expect(FunctionWords.holds("don\u{2019}t") && FunctionWords.holds("don't"))
    }
}
