// Tests that the rules engine hands its change ledger on, and that a result without a draft carries none.
import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The rules engine's change ledger")
struct RuleBasedChangeLedgerTests {
    @Test("the rules path returns where its passes changed the words")
    func rulesReturnLedger() async throws {
        let request = TransformationRequest(
            transcription: .fixture(text: "um we shipped it", language: .english))
        let result = try await RuleBasedTransformer().transform(request)
        let ledger = try #require(result.changeLedger)
        #expect(ledger.contains { $0.pass == .fillers && $0.kind == .removed && $0.writtenIndex == 0 })
    }

    @Test("a result with no draft, as the model path returns, has no ledger, and recording keeps one")
    func modelPathHasNone() {
        let model = TransformationResult(text: "We shipped it.", producedBy: .localModel)
        #expect(model.changeLedger == nil)
        let ledger = [ChangeLedgerEntry(writtenIndex: 0, pass: .fillers, kind: .removed)]
        let rules = TransformationResult(text: "We shipped it.", producedBy: .rules, changeLedger: ledger)
        #expect(rules.recording(nil).changeLedger == ledger)
    }
}
