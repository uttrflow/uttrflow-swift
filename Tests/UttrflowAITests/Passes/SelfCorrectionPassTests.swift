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
            ("at four wait at five", "at five"),
            ("at four no wait at five", "at five"),
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
        ]
    )
    func leavesUnmatched(input: String) {
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
