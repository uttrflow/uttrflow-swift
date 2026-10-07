import Testing
@testable import UttrflowPipeline

@Suite struct DoubtfulWordsTests {
    @Test func anOutcomeWithoutEvidenceSaysSoRatherThanListingNothing() {
        let outcome = DictationOutcome(text: "Hello there.", method: .clipboard, cleanedBy: .rules)
        #expect(outcome.doubtful == .notAvailable)
        #expect(outcome.doubtful != .placed([], unplaced: 0))
    }

    @Test func aSpanHoldsNoText() {
        let span = DoubtfulWordSpan(range: 1..<3, kind: .soundAlikeClass, evidence: 2)
        let fields = Mirror(reflecting: span).children
        #expect(fields.count == 3)
        for field in fields {
            #expect(
                !(field.value is String) && !(field.value is Substring), "\(field.label ?? "") holds text")
        }
    }

    @Test func thePlacedValueHoldsNoText() {
        let placed = DoubtfulWords.placed(
            [DoubtfulWordSpan(range: 0..<1, kind: .lowScore, evidence: 1)], unplaced: 1)
        guard case .placed(let spans, let unplaced) = placed else { Issue.record("not placed"); return }
        #expect(spans.count == 1 && unplaced == 1)
        #expect(!(Mirror(reflecting: placed).children.first?.value is String))
    }
}
