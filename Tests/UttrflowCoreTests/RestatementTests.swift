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

    @Test(
        "correction, strike that, or rather and actually make it each take back the half before them",
        arguments: [
            ("ten k correction twelve k", 2, 3, 0),
            ("pick the red one strike that the blue one", 4, 6, 1),
            ("tea or rather coffee", 1, 3, 0),
            ("ten k actually make it twelve k", 2, 5, 0),
            ("please order twenty no make it thirty boxes", 3, 6, 2),
            ("book the blue room actually make that the green room", 4, 7, 1),
        ]
    )
    func spokenCorrectionPhrasesAreTriggers(text: String, trigger: Int, restart: Int, start: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.triggerRun(at: trigger, in: live, of: draft) == restart - trigger)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == start)
    }

    @Test(
        "correction and or rather used as ordinary words take nothing back",
        arguments: [
            ("the correction was small", 1, 2),
            ("would you like to stay or rather not", 5, 7),
            ("i did not actually make that cake", 3, 6),
            ("we said no make it yourself", 2, 5),
        ]
    )
    func ordinaryUsesStay(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == nil)
    }

    @Test(
        "every contracted subject pronoun is as weak an anchor as the pronoun",
        arguments: [
            "he's", "she's", "we're", "we'll", "we've", "we'd", "you're", "you'll", "you've", "you'd",
            "they're", "they'll", "they've", "they'd", "he'll", "she'll", "that's", "there's",
            "i'm", "it's", "they\u{2019}re",
        ]
    )
    func contractedPronounsAreWeak(form: String) {
        #expect(Restatement.weakAnchors.contains(form))
    }

    @Test(
        "every Hindi subject word, romanised or in Devanagari, is as weak an anchor as an English one",
        arguments: [
            "main", "mai", "maine", "mujhe", "hum", "humne", "tum", "aap", "wo", "woh", "ye", "yeh",
            "mera", "meri", "mere", "tu", "tumne", "aapne", "usne", "unhone",
            "\u{092E}\u{0948}\u{0902}", "\u{0939}\u{092E}",
            "\u{0924}\u{0941}\u{092E}",
            "\u{0906}\u{092A}", "\u{0935}\u{094B}", "\u{0935}\u{0939}", "\u{092F}\u{0947}",
            "\u{092F}\u{0939}",
            "\u{092E}\u{0941}\u{091D}\u{0947}", "\u{092E}\u{0948}\u{0902}\u{0928}\u{0947}",
            "\u{092E}\u{0947}\u{0930}\u{093E}", "\u{092E}\u{0947}\u{0930}\u{0940}",
            "\u{092E}\u{0947}\u{0930}\u{0947}",
        ]
    )
    func hindiSubjectsAreWeak(form: String) {
        #expect(Restatement.isWeakAnchor(form))
    }

    @Test("the half taken back has to hold a word the speaker meant, not function words alone")
    func discardedHalfHoldsContent() {
        let good = reading("at four no sorry at five")
        #expect(Restatement.discardedStart(before: 2, after: 4, in: good.live, of: good.draft) == 0)
        let bare = reading("we need to no sorry to finish")
        #expect(Restatement.discardedStart(before: 3, after: 5, in: bare.live, of: bare.draft) == nil)
    }

    @Test(
        "a repeated verb takes back the whole first attempt before single-word replacement",
        arguments: [
            ("send the file to sam actually send the file to priya", 5, 6),
            ("book a table for two i mean book a table for four", 5, 7),
            ("open the red folder sorry open the blue folder", 4, 5),
            ("call the plumber no wait call the electrician", 3, 5),
            ("add milk i mean add sugar", 2, 4),
            ("tell sam scratch that tell priya to join", 2, 4),
        ]
    )
    func repeatedVerbTakesBackTheFirstAttempt(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == 0)
    }

    @Test(
        "a repeated phrase anchor can reach beyond six words",
        arguments: [
            ("send the file to the new client sorry send the file to the vendor", 7, 8),
            ("meet me at the cafe on main street sorry meet me at the cafe on first street", 8, 9),
            (
                "book a table for two at the italian place i mean book a table for four at the italian place",
                9, 11
            ),
            (
                "send the new file to the client in boston sorry send the new file to the vendor in paris",
                9, 10
            ),
        ])
    func repeatedPhraseAnchorCanReachFurther(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == 0)
    }

    @Test(
        "a camel-case dictionary anchor removes every spoken component",
        arguments: [
            ("push to git hub no wait GitHub", 4, 6, 2),
            ("open payment sheet scratch that PaymentSheet", 3, 5, 1),
            ("open user profile cache no wait UserProfileCache", 4, 6, 1),
        ]
    )
    func camelCaseDictionaryAnchorRemovesEverySpokenComponent(
        text: String, trigger: Int, restart: Int, expectedStart: Int
    ) {
        let (draft, live) = reading(text)
        #expect(
            Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft)
                == expectedStart)
    }

    @Test("a short whole-word anchor remains valid")
    func shortWholeWordAnchor() {
        let (draft, live) = reading("go no wait go")
        #expect(Restatement.discardedStart(before: 1, after: 3, in: live, of: draft) == 0)
    }

    @Test(
        "a lone repeated word does not anchor beyond six words",
        arguments: [
            ("at noon we will send the report to them no sorry at one", 9, 11),
            ("we need to book a table for six at the italian place on friday no sorry for eight", 14, 16),
        ])
    func loneWordAnchorKeepsTheShortReach(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == nil)
    }

    @Test("a repeated phrase anchor does not cross a sentence")
    func repeatedPhraseAnchorDoesNotCrossSentence() {
        let earlierSentence = reading("send the file. meet me at the cafe no send the file to vendor")
        #expect(
            Restatement.discardedStart(
                before: 8, after: 9, in: earlierSentence.live, of: earlierSentence.draft)
                == nil)
    }

    /// A trigger said with a pause comes back as its own sentence, which is read through rather than as a sentence end.
    @Test("a trigger that is a sentence of its own reads through the stop before it")
    func triggerAsItsOwnSentence() {
        let money = reading("The total is 40. No wait. 50.")
        #expect(Restatement.standsAlone(4, before: 6, in: money.live, of: money.draft))
        #expect(Restatement.discardedStart(before: 4, after: 6, in: money.live, of: money.draft) == 3)
        let meeting = reading("Meet me at four. Scratch that. At five.")
        #expect(Restatement.discardedStart(before: 4, after: 6, in: meeting.live, of: meeting.draft) == 2)
    }

    @Test("a stop that closes a question, an exclamation or a bare no is still a sentence end")
    func triggerAsItsOwnSentenceNeedsAPlainStop() {
        let question = reading("Is it 3? No wait. 4.")
        #expect(!Restatement.standsAlone(3, before: 5, in: question.live, of: question.draft))
        #expect(Restatement.discardedStart(before: 3, after: 5, in: question.live, of: question.draft) == nil)
        let answer = reading("The code is 45. No. 46.")
        #expect(!Restatement.standsAlone(4, before: 5, in: answer.live, of: answer.draft))
        let running = reading("Meet at four. No wait at five.")
        #expect(!Restatement.standsAlone(3, before: 5, in: running.live, of: running.draft))
        let shouted = reading("Meet at four. No wait! At five.")
        #expect(!Restatement.standsAlone(3, before: 5, in: shouted.live, of: shouted.draft))
        #expect(!Restatement.standsAlone(0, before: 2, in: shouted.live, of: shouted.draft))
    }

    @Test("anchors on an amount written with its sign")
    func anchorsOnASignedAmount() {
        let money = reading("the total is $40, no wait, $50.")
        #expect(Restatement.discardedStart(before: 4, after: 6, in: money.live, of: money.draft) == 3)
        let share = reading("the fee is 40% actually 50%.")
        #expect(Restatement.discardedStart(before: 4, after: 5, in: share.live, of: share.draft) == 3)
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

    /// The unit repeated after each number belongs to the quantity, so it does not hide the number it follows.
    @Test(
        "a number correction takes the quantity back when the restatement repeats its unit",
        arguments: [
            ("we need twelve boxes i mean fifteen boxes", 4, 6, 2),
            ("the total is forty dollars no wait fifty dollars", 5, 7, 3),
            ("it costs forty dollars sorry fifty dollars", 4, 5, 2),
            ("invite ten people no wait twelve people", 3, 5, 1),
            ("we need twenty five boxes i mean thirty boxes", 5, 7, 2),
            ("send it to twelve elm road sorry twenty one elm road", 6, 7, 3),
            ("we need ten boxes of paper i mean twelve boxes of paper", 6, 8, 2),
        ])
    func numberWithItsUnit(text: String, trigger: Int, restart: Int, start: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == start)
    }

    @Test(
        "a number correction does not step over a unit that differs, ends a sentence, or is not repeated",
        arguments: [
            ("ten apples actually twelve pears", 2, 3),
            ("we ordered ten boxes. no twelve boxes arrived", 4, 5),
            ("i counted ten. boxes no twelve boxes", 4, 5),
            ("we need ten boxes no twelve. boxes", 4, 5),
            ("ten boxes no twelve", 2, 3),
            ("boxes no twelve boxes", 1, 2),
            ("ten apples, actually twelve pears", 2, 3),
            ("ten boxes, no twelve", 2, 3),
            ("ten boxes sorry twelve", 2, 3),
            ("ten apples i mean twelve pears", 2, 4),
            ("boxes no wait twelve boxes", 1, 3),
            ("i counted ten. boxes sorry twelve boxes", 4, 5),
            ("we need ten boxes i mean twelve. boxes", 4, 6),
            ("send it to twelve elm road sorry twenty one oak road", 6, 7),
            ("ten boxes of paper no wait twelve boxes", 4, 6),
            ("i counted ten. elm road sorry twelve elm road", 5, 6),
            ("send it to twelve elm road sorry twenty one elm. road", 6, 7),
        ])
    func numberWithAnotherUnit(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == nil)
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

    @Test(
        "does not treat a reported answer after a copula as a restatement",
        arguments: [
            ("The vote was no, the board will not proceed", 3, 4),
            ("The exit code was no, the script did not run", 4, 5),
            ("The result was no, the sample did not match", 3, 4),
            ("The status was no, the order is held", 3, 4),
            ("Tell her the vote is no, the plan stays", 5, 6),
        ]
    )
    func reportedAnswerIsNotADiscardedHalf(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == nil)
    }

    /// The frame here opens on "ship", not on an answer, so the correction still stands.
    @Test("still matches a correction in a sentence that opens with an answer")
    func correctionAfterAnAnswerStillMatches() {
        let ship = reading("yes we ship on the third no sorry on the fourth")
        #expect(Restatement.discardedStart(before: 6, after: 8, in: ship.live, of: ship.draft) == 3)
    }

    @Test(
        "ordinary actually and no do not replace a content word without a pause",
        arguments: [
            ("the weather actually improved overnight", 2, 3),
            ("sales actually grew last quarter", 1, 2),
            ("the server actually crashed again", 2, 3),
            ("the team actually shipped the release", 2, 3),
            ("she gave no reason", 2, 3),
            ("he said no thanks to the offer", 2, 3),
        ]
    )
    func ordinaryActuallyAndNoNeedPause(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == nil)
    }

    @Test("a pause after the discarded word still corroborates actually and no corrections")
    func pauseCorroboratesSingleWordCorrection() {
        let actually = reading("the blue, actually green")
        #expect(Restatement.discardedStart(before: 2, after: 3, in: actually.live, of: actually.draft) == 1)
        let no = reading("the red, no blue")
        #expect(Restatement.discardedStart(before: 2, after: 3, in: no.live, of: no.draft) == 1)
    }

    /// A trigger with nothing before it takes nothing back, however the word after it looks.
    @Test(
        "a trigger at word 0 takes nothing back, so the call never reads before the start",
        arguments: [
            ("actually three", 0, 1),
            ("actually word", 0, 1),
        ])
    func triggerAtStartTakesNothingBack(text: String, trigger: Int, restart: Int) {
        let (draft, live) = reading(text)
        #expect(Restatement.discardedStart(before: trigger, after: restart, in: live, of: draft) == nil)
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
