import Testing

@testable import UttrflowCore

@Suite("Mark spacing table")
struct MarkSpacingTests {
    @Test("every row is one mark, and the table loads from the bundle")
    func rowsAreSingleMarks() {
        #expect(MarkSpacing.table.rows.count >= 20)
        #expect(MarkSpacing.table.rows.allSatisfy { $0.id.count == 1 })
    }

    @Test("every spoken mark with a row takes its side from the table")
    func spokenMarksAgree() {
        let listed = SpokenCommands.marks.filter {
            $0.text.count == 1 && MarkSpacing.kind(of: Character($0.text)) != nil
        }
        #expect(!listed.isEmpty)
        for mark in listed {
            #expect(mark.placement == MarkSpacing.kind(of: Character(mark.text)), "\(mark.id)")
        }
    }

    @Test("a straight quote has no row, because its side depends on where it stands")
    func straightQuotesUnlisted() {
        #expect(MarkSpacing.kind(of: "\"") == nil)
        #expect(MarkSpacing.kind(of: "'") == nil)
    }
}
