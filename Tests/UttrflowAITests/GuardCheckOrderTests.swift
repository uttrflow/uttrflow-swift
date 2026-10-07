import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// The guard's checks as an ordered list: the order is data, the first refusal wins, and every failing check can be listed.
@Suite("GuardCheckOrder")
struct GuardCheckOrderTests {
    private let sut = MeaningPreservationGuard()

    @Test("the checks run in the order the first refusal is taken")
    func order() {
        #expect(
            MeaningPreservationGuard.checks.map(\.name) == [
                "empty", "preamble", "length", "numbers", "symbols", "spokenPunctuation", "removal",
                "readings", "confidentHomophone", "layout", "grammar",
            ])
    }

    @Test("only the preamble check is excused by an offered reading")
    func excusable() {
        #expect(MeaningPreservationGuard.checks.filter(\.excusedByOfferedReading).map(\.name) == ["preamble"])
    }

    @Test("every failing check is listed, and the verdict is the first of them")
    func failingChecks() {
        let draft = Draft(text: "send the report to the team on friday")
        let rewritten = "Here is: send 40 reports!"
        let failing = sut.failingChecks(draft: draft, rewritten: rewritten)
        #expect(failing.map(\.name).starts(with: ["preamble", "numbers", "symbols"]))
        #expect(failing.first?.verdict == sut.verdict(draft: draft, rewritten: rewritten))
    }

    @Test("an accepted rewrite fails no check")
    func noneFailing() {
        let draft = Draft(text: "send the report to the team on friday")
        #expect(sut.failingChecks(draft: draft, rewritten: "Send the report to the team on Friday.").isEmpty)
    }
}
