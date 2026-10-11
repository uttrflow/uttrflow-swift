// Tests that every change the rules path ledgers lands on a word of the text it wrote, with no alignment.
import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Locating the rules path's change ledger in its written text")
struct ChangeLedgerLocationTests {
    /// Invented rules-path dictations covering fillers, stammers, repeats, self-correction, spoken marks and layout.
    static let fixtures = [
        "um we shipped it",
        "so the the build is green",
        "send it to the team uh tomorrow",
        "we meet at three no wait four",
        "the release went out comma and the tests passed full stop",
        "hello there exclamation mark",
        "first point new line second point",
        "um uh so we we need the new new report",
        "add milk new paragraph bullet eggs bullet bread",
        "I think I think we should ship it question mark",
    ]

    private func transformed(_ text: String) async throws -> TransformationResult {
        try await RuleBasedTransformer().transform(
            TransformationRequest(transcription: .fixture(text: text, language: .english)))
    }

    @Test("no ledgered change is unlocated on the rules path", arguments: fixtures)
    func everyEntryLocated(_ text: String) async throws {
        let result = try await transformed(text)
        let ledger = try #require(result.changeLedger)
        let written = ChangeLedgerEntry.writtenWords(of: result.text)
        let unlocated = ledger.filter { $0.location(in: written) == nil }
        #expect(unlocated.isEmpty, "\(text) -> \(result.text): \(unlocated)")
    }

    @Test("the fixture set has changes to locate, and the unlocated fraction is 0")
    func fractionIsZero() async throws {
        var total = 0
        var unlocated = 0
        for text in Self.fixtures {
            let result = try await transformed(text)
            let written = ChangeLedgerEntry.writtenWords(of: result.text)
            let ledger = result.changeLedger ?? []
            total += ledger.count
            unlocated += ledger.filter { $0.location(in: written) == nil }.count
        }
        #expect(total > Self.fixtures.count)
        #expect(unlocated == 0, "\(unlocated) of \(total)")
    }

    @Test("the ledger reads as the expected labelled list")
    func labelledList() async throws {
        let result = try await transformed("um we shipped it")
        let written = ChangeLedgerEntry.writtenWords(of: result.text)
        let filler = try #require(result.changeLedger?.first { $0.pass == .fillers })
        #expect(filler.kind == .removed)
        #expect(filler.location(in: written) == .word(written[0]))
        #expect(filler.evidence == nil)
    }
}
