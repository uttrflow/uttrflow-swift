// Tests the change ledger read from a draft's own edit chains.
import Foundation
import Testing

@testable import UttrflowCore

@Suite("ChangeLedger")
struct ChangeLedgerTests {
    /// "um send the the report to marlow" with the filler and stammer removed, one word replaced and one inserted.
    static func edited() -> Draft {
        var draft = Draft(text: "um send the the report to marlow")
        draft.remove(at: 0, by: .fillers)
        draft.remove(at: 2, by: .stammers)
        draft.replace(at: 6, with: "Marlowe", by: "dictionary")
        draft.insert("please", at: 1, by: "test")
        return draft
    }

    @Test("locates every edit at its written position with its pass and kind, without alignment")
    func locatesEveryEdit() {
        #expect(
            Self.edited().changeLedger == [
                ChangeLedgerEntry(writtenIndex: 0, pass: .fillers, kind: .removed),
                ChangeLedgerEntry(writtenIndex: 0, pass: "test", kind: .inserted),
                ChangeLedgerEntry(writtenIndex: 2, pass: .stammers, kind: .removed),
                ChangeLedgerEntry(writtenIndex: 5, pass: "dictionary", kind: .replaced),
            ])
    }

    @Test("an untouched draft has an empty ledger, so nothing is left unlocated on the rules path")
    func untouchedIsEmpty() {
        #expect(Draft(text: "send the report").changeLedger.isEmpty)
    }

    @Test("the encoded ledger holds no heard or written word")
    func encodedHoldsNoWords() throws {
        let data = try JSONEncoder().encode(Self.edited().changeLedger)
        let encoded = try #require(String(data: data, encoding: .utf8)).lowercased()
        for word in ["um", "send", "the", "report", "marlow", "please"] {
            #expect(!encoded.contains("\"\(word)") && !encoded.contains(word + "\""), "\(word)")
        }
        #expect(!encoded.contains("marlow"))
        #expect(try JSONDecoder().decode([ChangeLedgerEntry].self, from: data) == Self.edited().changeLedger)
    }
}
