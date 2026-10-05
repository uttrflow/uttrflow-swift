// Tests for resolving a command scope against the insertion ledger into a field range.

import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("A command scope resolves against the ledger to a field range")
struct InsertionRecordScopeTests {
    private static let field = FieldIdentity(processIdentifier: 7, windowNumber: 3, element: 11)

    private func record(_ text: String, endingAt end: Int) -> InsertionRecord {
        InsertionRecord(field: Self.field, range: (end - text.utf16.count)..<end, text: text)
    }

    @Test("an empty ledger refuses every scope", arguments: CommandScope.allCases)
    func refusesEmptyLedger(_ scope: CommandScope) {
        #expect(scope.span(in: []) == nil)
    }

    @Test("word, clause and sentence divide the newest insertion, in UTF-16 field offsets")
    func dividesNewest() {
        let records = [record("Héllo. Send it, now.", endingAt: 120)]
        #expect(CommandScope.word.span(in: records)?.range == 115..<120)
        #expect(CommandScope.clause.span(in: records)?.range == 115..<120)
        #expect(CommandScope.sentence.span(in: records)?.range == 106..<120)
        #expect(CommandScope.sentence.span(in: records)?.text == " Send it, now.")
    }

    @Test("a piece is the newest insertion only")
    func pieceIsNewest() {
        let records = [record("One.", endingAt: 10), record(" Two.", endingAt: 15)]
        #expect(CommandScope.piece.span(in: records)?.range == 10..<15)
    }

    @Test("a dictation runs back through insertions written end to end, and stops at a gap")
    func dictationRunsBackToAGap() {
        let records = [
            record("Old.", endingAt: 4), record("One.", endingAt: 10), record(" Two.", endingAt: 15),
        ]
        #expect(CommandScope.dictation.span(in: records)?.range == 6..<15)
        #expect(CommandScope.dictation.span(in: records)?.text == "One. Two.")
        #expect(CommandScope.default.span(in: records)?.range == 6..<15)
    }

    @Test("a blank newest insertion refuses a dividing scope")
    func blankNewestRefuses() {
        #expect(CommandScope.word.span(in: [record("  ", endingAt: 5)]) == nil)
    }
}
