import UttrflowCore
import Testing

@testable import UttrflowAI

/// A number word that counts something, or stands after a determiner, is the number said, so its sound-alike is never offered.
@Suite("A counting number word is never offered a sound-alike", .bug(id: 8105))
struct CountingNumberDoubtTests {
    private func spans(_ text: String) async -> [DoubtfulSpan] {
        await DoubtfulWords.standard.spans(in: Draft.heard(text), for: .unknown)
    }

    private func offered(_ found: [DoubtfulSpan], for heard: String) -> [String] {
        found.filter { $0.heard == heard }.flatMap { $0.candidates.map(\.spelling) }
    }

    @Test(
        "a number word read as a count is offered no reading, heard surely or not",
        arguments: [
            ("we hired three engineers and ?two designers this quarter", "two"),
            ("we hired three engineers and two designers this quarter", "two"),
            ("this is the ?one i was thinking of", "one"),
            ("this is the one i was thinking of", "one"),
            ("we need ?four new chairs", "four"),
        ])
    func countingNumberGetsNoReading(text: String, number: String) async {
        let found = await spans(text)
        #expect(offered(found, for: number).isEmpty, "\(number) was offered \(offered(found, for: number))")
    }

    @Test(
        "a number word that is no count is offered its partner only on evidence, which these have none of",
        arguments: [
            ("our team ?one the hackathon last weekend", "one", "won"),
            ("this is ?four you", "four", "for"),
        ])
    func numberWithoutEvidenceGetsNoReading(text: String, heard: String, partner: String) async {
        let found = await spans(text)
        #expect(!offered(found, for: heard).contains(partner), "got \(offered(found, for: heard))")
    }
}
