import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("SelfCorrectionPass")
struct SelfCorrectionPassTests {
    private let sut = SelfCorrectionPass()

    @Test(
        "replaces a restated phrase with its restatement",
        arguments: [
            ("let's meet at four no sorry at five on tuesday", "let's meet at five on tuesday"),
            ("send it on tuesday I mean on wednesday", "send it on wednesday"),
            ("the red one scratch that the blue one", "the blue one"),
            ("at four never mind at five", "at five"),
            ("at four wait sorry at five", "at five"),
            ("at four no wait at five", "at five"),
            ("call me no call me later", "call me later"),
            ("at four, no sorry, at five", "at five"),
            ("put it on the table no sorry on the shelf", "put it on the shelf"),
            ("at four no sorry at five I mean at six", "at six"),
            (
                "I'll bring the cake and the drinks no wait and the plates",
                "I'll bring the cake and the plates"
            ),
        ]
    )
    func replacesRestatement(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "replaces a number with the number said after the trigger",
        arguments: [
            ("coffee at 2 actually 3", "coffee at 3"),
            ("coffee at two actually three", "coffee at three"),
            ("call at two thirty actually three", "call at three"),
            ("I have two no three cats", "I have three cats"),
        ]
    )
    func replacesNumber(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A number anchor may not reach back through a full stop, because the number in the sentence before was not the one corrected. See `Docs/cleanup.md`.
    @Test(
        "leaves a number the speaker said in the sentence before the correction",
        arguments: [
            "the meeting is at 3. no 4 people confirmed",
            "the meeting is at three. no four people confirmed",
            "the meeting is at 3! no 4 people confirmed",
            "the meeting is at 3? no 4 people confirmed",
            "the code is 4 5. no 6",
            "call at 2:30. no 3",
            "room 5. actually 6",
        ]
    )
    func leavesNumbersBeforeASentenceEnd(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// The correction still runs inside its own sentence, reaching back only as far as the stop.
    @Test(
        "corrects the number in this sentence without taking the one in the last",
        arguments: [
            ("the code is 4. 5 no 6", "the code is 4. 6"),
            ("we booked 7. 8 actually 9", "we booked 7. 9"),
        ]
    )
    func correctsWithinTheSentence(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves everything, trigger included, when the halves do not match",
        arguments: [
            "no I don't think so",
            "I actually enjoyed it",
            "sorry I'm late",
            "I mean it",
            "the meeting is at four actually",
            "I can't come to the party no I have to work",
            "meet at four. no at five",
            "at noon we will send the report to them no sorry at one",
            "the meeting is at four I mean it's at five",
            "wait for me",
            // "wait" alone is a verb far more often than a trigger, so it needs "no" or "sorry" beside it.
            "at four wait at five",
            "grab a coffee and wait a moment",
            "we need to wait to finish the review",
        ]
    )
    func leavesUnmatched(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// Only a trigger phrase marks a correction; a phrase said twice over is a list far more often. See `Docs/cleanup.md`.
    @Test(
        "leaves a phrase repeated with no trigger exactly as it was said",
        arguments: [
            "I'll pay for lunch for everyone",
            "coffee with milk with sugar",
            "the meeting is on Monday on Zoom",
            "I wanted to buy a record as a gift as a present",
            "let's meet on tuesday on wednesday afternoon",
            "send it to the office in london in paris",
            "I like tea I like coffee both are fine",
            "she said she said nothing of the sort",
            "as soon as possible we should ship",
            "the good the bad and the ugly",
        ]
    )
    func leavesUntriggeredRepeats(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A trigger heading a repeated frame coordinates a list, and the first item is not a discarded half. See `Docs/cleanup.md`.
    @Test(
        "leaves a coordinated list whose items are headed by the trigger word itself",
        arguments: [
            "I said no to the offer, no to the meeting",
            "say sorry to John, sorry to Marcy too",
            "say no to the offer no to the meeting",
            "there's no room, no room at all",
            "say no 3 no 4",
            "the bus is no 7 no 8",
        ]
    )
    func leavesTriggerHeadedLists(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records the discarded half and the trigger as removed by this pass")
    func provenance() {
        let draft = sut.apply(Draft(text: "at four no sorry at five"))
        #expect(draft.words.map(\.isPresent) == [false, false, false, false, true, true])
        #expect(draft.removed.allSatisfy { $0.state == .removed(by: SelfCorrectionPass.id) })
        #expect(draft.originalText == "at four no sorry at five")
    }
}
