import Testing

@testable import UttrflowAI

/// What the rewrite put where each run of the kept draft stood, which is what every positional check reads.
@Suite("Aligning a rewrite with the draft")
struct RewriteAlignmentTests {
    private func aligned(_ kept: String, _ rewritten: String) -> RewriteAlignment {
        RewriteAlignment(kept: kept, rewritten: rewritten)
    }

    @Test("a rewrite that only repunctuates changes nothing")
    func punctuationIsNoChange() {
        let alignment = aligned("hey john i'll be late", "Hey John, I'll be late.")
        #expect(alignment.changes.isEmpty)
    }

    @Test("a replaced word is one change at its own place")
    func oneReplacement() {
        let alignment = aligned("the main thing is money", "The main thing is mine.")
        #expect(alignment.changes == [RewriteAlignment.Change(kept: 4..<5, rewritten: 4..<5)])
        #expect(alignment.keptSpelling(of: 4..<5) == "money")
        #expect(alignment.rewrittenSpelling(of: 4..<5) == "mine")
    }

    @Test("a word said twice is changed only where it changed")
    func repeatsAreToldApart() {
        let alignment = aligned("call mark before mark leaves", "Call Mark before Mike leaves.")
        #expect(alignment.changes == [RewriteAlignment.Change(kept: 3..<4, rewritten: 3..<4)])
        #expect(alignment.rewrittenWords(of: 3..<4) == ["mike"])
    }

    @Test("two words closed into one are one change, and their spellings meet")
    func manyToOne() {
        let alignment = aligned("the crash is in payment sheet", "The crash is in PaymentSheet.")
        #expect(alignment.changes == [RewriteAlignment.Change(kept: 4..<6, rewritten: 4..<5)])
        #expect(alignment.keptSpelling(of: 4..<6) == "paymentsheet")
        #expect(alignment.rewrittenSpelling(of: 4..<5) == "paymentsheet")
    }

    @Test("a word dropped and a word added leave a run empty on their own side")
    func emptyRuns() {
        let dropped = aligned("we ship the thing friday", "We ship the thing.")
        #expect(dropped.changes == [RewriteAlignment.Change(kept: 4..<5, rewritten: 4..<4)])
        #expect(dropped.rewrittenWords(of: 4..<4).isEmpty)

        let added = aligned("we ship friday", "We ship the thing Friday.")
        #expect(added.changes == [RewriteAlignment.Change(kept: 2..<2, rewritten: 2..<4)])
        #expect(added.keptSpelling(of: 2..<2).isEmpty)
    }

    @Test("two separate changes are reported in the order they stand")
    func changesComeInOrder() {
        let alignment = aligned(
            "the invoice is 400 and the credit is 900", "The invoice is 900 and the credit is 400.")
        #expect(alignment.changes.map(\.kept) == [3..<4, 8..<9])
    }

    @Test("a spelling is found at every run of kept words that closes up to it")
    func runsAreFoundBySpelling() {
        let repeated = aligned("call mark before mark leaves", "Call Mark before Mike leaves.")
        #expect(repeated.keptRuns(spelled: "mark") == [1..<2, 3..<4])

        let joined = aligned("the crash is in payment sheet", "The crash is in PaymentSheet.")
        #expect(joined.keptRuns(spelled: "paymentsheet") == [4..<6])
        #expect(joined.keptRuns(spelled: "cream").isEmpty)
        #expect(joined.keptRuns(spelled: "").isEmpty)
    }

    @Test("a run reads as the words standing in its place, whether or not the whole of it changed")
    func aRunReadsAsWhatStandsThere() {
        let partly = aligned("the ice cream is cold", "The ice screams is cold.")
        #expect(partly.changes.map(\.kept) == [2..<3])
        #expect(partly.standing(in: 1..<3) == "icescreams")
        #expect(partly.standing(in: 3..<5) == "iscold")

        let wholly = aligned("the ice cream is cold", "The I scream is cold.")
        #expect(wholly.standing(in: 1..<3) == "iscream")
    }

    @Test("a text with nothing in it aligns with anything and asks for no run")
    func emptyTexts() {
        #expect(aligned("", "").changes.isEmpty)
        #expect(
            aligned("", "hello there").changes == [RewriteAlignment.Change(kept: 0..<0, rewritten: 0..<2)])
        #expect(
            aligned("hello there", "").changes == [RewriteAlignment.Change(kept: 0..<2, rewritten: 0..<0)])
    }
}
