import UttrflowCore
import Testing

@testable import UttrflowAI

/// A coordinating conjunction joins two alternatives or additions, so a sound-alike never replaces one.
@Suite("Coordinators are never offered another reading", .bug(id: 7994))
struct CoordinatorDoubtTests {
    private func spans(_ text: String) async -> [DoubtfulSpan] {
        await DoubtfulWords.standard.spans(in: Draft.heard(text), for: .unknown)
    }

    @Test(
        "a coordinator heard at a low score is offered no reading",
        arguments: ["or", "and", "but", "nor"])
    func lowScoreCoordinatorGetsNoReading(coordinator: String) async {
        let found = await spans("it costs about $49 a month ?\(coordinator) $450 if you pay annually")
        #expect(
            !found.contains { $0.heard.lowercased() == coordinator },
            "a coordinator was offered readings: \(found.map { ($0.heard, $0.candidates.map(\.spelling)) })")
    }

    @Test("a surely heard coordinator is offered no reading either")
    func sureCoordinatorGetsNoReading() async {
        let found = await spans("it costs about $49 a month or $450 if you pay annually")
        #expect(!found.contains { $0.heard == "or" })
    }

    @Test("a homophone beside a coordinator is still offered its partner where its slot rules it out")
    func neighbouringHomophoneStillOffered() async {
        let found = await spans("send it too me or leave")
        #expect(found.contains { $0.heard == "too" && $0.candidates.map(\.spelling).contains("to") })
    }
}
