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

    /// A number anchor reaches back only as far as the stop, because the number in the sentence before was not the one corrected.
    @Test("refuses a number anchor that sits on the far side of a sentence end")
    func numbersDoNotReachThroughAStop() {
        let people = reading("the meeting is at 3. no 4 people confirmed")
        #expect(Restatement.discardedStart(before: 5, after: 6, in: people.live, of: people.draft) == nil)
        let spelled = reading("the meeting is at three. no four people confirmed")
        #expect(
            Restatement.discardedStart(before: 5, after: 6, in: spelled.live, of: spelled.draft) == nil)
        let run = reading("the code is 4 5. no 6")
        #expect(Restatement.discardedStart(before: 5, after: 6, in: run.live, of: run.draft) == nil)
    }

    /// The walk-back over a run of numbers stops at the stop, so the correction takes back only this sentence's half.
    @Test("a number anchor whose neighbour ends a sentence reaches back no further")
    func numberWalkBackStopsAtTheStop() {
        let code = reading("the code is 4. 5 no 6")
        #expect(Restatement.discardedStart(before: 5, after: 6, in: code.live, of: code.draft) == 4)
    }

    /// A trigger heading a repeated frame — "no to the offer, no to the meeting" — coordinates a list rather than correcting one.
    @Test("refuses the match when the trigger word itself heads the half it would take back")
    func triggerHeadingAList() {
        let offer = reading("i said no to the offer, no to the meeting")
        #expect(Restatement.discardedStart(before: 6, after: 7, in: offer.live, of: offer.draft) == nil)
        let apology = reading("say sorry to john, sorry to marcy too")
        #expect(
            Restatement.discardedStart(before: 4, after: 5, in: apology.live, of: apology.draft) == nil)
        let room = reading("there's no room, no room at all")
        #expect(Restatement.discardedStart(before: 3, after: 4, in: room.live, of: room.draft) == nil)
        let numbered = reading("say no 3 no 4")
        #expect(
            Restatement.discardedStart(before: 3, after: 4, in: numbered.live, of: numbered.draft) == nil)
    }

    /// "Yes … no …" and "thanks … sorry …" are two items of one pair: the speaker answered twice, and took nothing back.
    @Test("refuses the match when the trigger answers the word the half opens after")
    func triggerAnsweringAnotherHead() {
        let offer = reading("i said yes to the offer no to the meeting")
        #expect(Restatement.discardedStart(before: 6, after: 7, in: offer.live, of: offer.draft) == nil)
        let apology = reading("say thanks to john sorry to marcy too")
        #expect(
            Restatement.discardedStart(before: 4, after: 5, in: apology.live, of: apology.draft) == nil)
    }

    /// The frame here opens on "ship", not on an answer, so the correction still stands.
    @Test("still matches a correction in a sentence that opens with an answer")
    func correctionAfterAnAnswerStillMatches() {
        let ship = reading("yes we ship on the third no sorry on the fourth")
        #expect(Restatement.discardedStart(before: 6, after: 8, in: ship.live, of: ship.draft) == 3)
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
