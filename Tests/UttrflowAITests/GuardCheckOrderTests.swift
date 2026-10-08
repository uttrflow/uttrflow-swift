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

    @Test("no two checks share a name, so a result names exactly one check")
    func uniqueNames() {
        let names = MeaningPreservationGuard.checks.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(MeaningPreservationGuard.textChecks.map(\.name) == Array(names.prefix(5)))
    }

    @Test("only the preamble check is excused by an offered reading")
    func excusable() {
        #expect(MeaningPreservationGuard.checks.filter(\.excusedByOfferedReading).map(\.name) == ["preamble"])
    }

    @Test("every failing check is listed, and the verdict is the first of them")
    func failingChecks() {
        let draft = Draft(text: "send the report to the team on friday")
        let rewritten = "Here is: send 40 reports!"
        let failing = sut.checkResults(on: GuardInput(draft: draft, rewritten: rewritten))
            .filter { !$0.verdict.isAccepted }
        #expect(failing.map(\.name).starts(with: ["preamble", "numbers", "symbols"]))
        #expect(failing.first?.verdict == sut.verdict(draft: draft, rewritten: rewritten))
    }

    @Test("an accepted rewrite fails no check")
    func noneFailing() {
        let draft = Draft(text: "send the report to the team on friday")
        let results = sut.checkResults(
            on: GuardInput(draft: draft, rewritten: "Send the report to the team on Friday."))
        #expect(results.filter { !$0.verdict.isAccepted }.isEmpty)
        #expect(results.map(\.name) == MeaningPreservationGuard.checks.map(\.name))
    }

    @Test("the transformer lists every check on its answer, script first, and refuses with the first")
    func transformerExplains() async throws {
        let model = FakeCleanupModel { _ in "I did tell Mary not to call John." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let request = TransformationRequest(
            transcription: .fixture(text: "I did not tell Mary to call John", language: .english))
        let judged = try await sut.explainGuard(request)
        #expect(judged.answer == "I did tell Mary not to call John.")
        #expect(judged.finished == "I did tell Mary not to call John.")
        #expect(judged.checks.map(\.name) == ["script"] + MeaningPreservationGuard.checks.map(\.name))
        let refusals = judged.checks.filter { !$0.verdict.isAccepted }
        #expect(refusals.map(\.name) == ["grammar"])
        do {
            _ = try await sut.transform(request)
            Issue.record("expected the moved negation to be refused")
        } catch {
            guard case .outputRejected(let reason, let kind) = error else {
                Issue.record("expected outputRejected, got \(error)")
                return
            }
            #expect(refusals.first?.verdict == .rejected(reason: reason, kind: kind))
        }
    }
}
