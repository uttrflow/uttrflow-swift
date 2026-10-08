// Tests that a History row's "What changed" reads its stored ledger, and says nothing when it has none.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowHistory

@Suite("What changed, read from the stored ledger")
struct WhatChangedTests {
    private let when = Date(timeIntervalSince1970: 1_000)

    @Test("each ledger entry becomes a line at its written word, keeping pass, kind and evidence")
    func readsLedger() {
        let record = DictationRecord(
            text: "We shipped it.", when: when,
            changeLedger: [
                ChangeLedgerEntry(writtenIndex: 0, pass: .fillers, kind: .removed),
                ChangeLedgerEntry(writtenIndex: 2, pass: "dictionary", kind: .replaced, evidence: .single),
                ChangeLedgerEntry(writtenIndex: 3, pass: .stammers, kind: .removed),
            ])
        #expect(
            record.whatChanged == [
                WhatChangedLine(pass: .fillers, kind: .removed, evidence: nil, location: .word("We")),
                WhatChangedLine(
                    pass: "dictionary", kind: .replaced, evidence: .single, location: .word("it.")),
                WhatChangedLine(pass: .stammers, kind: .removed, evidence: nil, location: .end),
            ])
    }

    @Test("a row without a ledger has no lines, so the caller falls back rather than showing nothing changed")
    func noLedger() {
        #expect(DictationRecord(text: "We shipped it.", when: when).whatChanged == nil)
        #expect(DictationRecord(text: "We shipped it.", when: when, changeLedger: []).whatChanged == [])
    }

    @Test("an entry past the text is unlocated, not moved onto another word")
    func pastTheText() {
        let record = DictationRecord(
            text: "Hi", when: when,
            changeLedger: [ChangeLedgerEntry(writtenIndex: 4, pass: .fillers, kind: .inserted)])
        #expect(record.whatChanged?.map(\.location) == [nil])
    }
}
