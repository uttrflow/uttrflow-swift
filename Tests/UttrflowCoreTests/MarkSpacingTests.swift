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

    @Test("every joining row says whether a space sets it apart, and only a joining row says so")
    func joiningRowsStateTheirSpacing() {
        for row in MarkSpacing.table.rows {
            #expect((row.kind == .joining) == (row.spaced != nil), "\(row.id)")
        }
        #expect(MarkSpacing.spacesJoin("\u{2014}"))
        for mark in "-\u{2013}/,(" { #expect(!MarkSpacing.spacesJoin(mark), "\(mark)") }
    }

    @Test("a spaced joining mark goes after a space, a glued one straight on the word")
    func markedReadsTheTable() {
        #expect(WordShape.marked("home", with: "\u{2014}") == "home \u{2014}")
        #expect(WordShape.marked("pages", with: "\u{2013}") == "pages\u{2013}")
        #expect(WordShape.marked("and", with: "/") == "and/")
    }

    @Test("a straight quote has no row, because its side depends on where it stands")
    func straightQuotesUnlisted() {
        #expect(MarkSpacing.kind(of: "\"") == nil)
        #expect(MarkSpacing.kind(of: "'") == nil)
    }
}
