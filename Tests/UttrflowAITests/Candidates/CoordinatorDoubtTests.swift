import Testing
import UttrflowCore

@testable import UttrflowAI

/// A coordinating conjunction joins two alternatives or two additions, so no sound-alike is ever offered in its place.
@Suite("Coordinator doubt")
struct CoordinatorDoubtTests {
    private func draft(_ text: String, doubting word: String, at confidence: Double) -> Draft {
        Draft(
            words: text.split(whereSeparator: \.isWhitespace).map {
                let spoken = String($0)
                let bare = spoken.trimmingCharacters(in: .punctuationCharacters)
                return Draft.Word(spoken, evidence: .score(bare == word ? confidence : 0.95))
            })
    }

    @Test(
        "a doubted coordinator is offered no reading",
        arguments: [
            ("it costs about $49 a month, or $450 if you pay annually", "or"),
            ("we can ship on friday, or on monday if the truck is late", "or"),
            ("send the invoice and the receipt today", "and"),
            ("it is small but it is loud", "but"),
        ])
    func coordinatorGetsNoReading(text: String, word: String) async {
        let doubted = draft(text, doubting: word, at: 0.3)
        let spans = await DoubtfulWords.standard.spans(in: doubted, for: .unknown)
        #expect(!spans.contains { $0.heard == word }, "offered \(spans.map { ($0.heard, $0.candidates.map(\.spelling)) })")
    }
}
