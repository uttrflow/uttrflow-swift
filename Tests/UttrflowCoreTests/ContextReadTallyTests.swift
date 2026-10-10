import Testing

@testable import UttrflowCore

@Suite("ContextReadTally")
struct ContextReadTallyTests {
    @Test("each rung is counted under its own application", arguments: ContextReadRung.allCases)
    func countsEachRung(rung: ContextReadRung) {
        var tally = ContextReadTally()
        tally.add(rung, in: "com.example.editor")
        tally.add(rung, in: "com.example.editor")
        tally.add(rung, in: "com.example.chat")

        #expect(tally.counts["com.example.editor"] == [rung: 2])
        #expect(tally.counts["com.example.chat"] == [rung: 1])
    }

    @Test("one application keeps a separate count per rung")
    func separatesRungs() {
        var tally = ContextReadTally()
        tally.add(.rangedValue, in: "com.example.editor")
        tally.add(.wholeValue, in: "com.example.editor")
        tally.add(.wholeValue, in: "com.example.editor")

        #expect(tally.counts == ["com.example.editor": [.rangedValue: 1, .wholeValue: 2]])
    }
}
