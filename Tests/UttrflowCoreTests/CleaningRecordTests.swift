import Testing

@testable import UttrflowCore

@Suite("What the clean-up steps did")
struct CleaningRecordTests {
    /// The draft a filler pass and a number pass have both been over.
    private func draft() -> Draft {
        var draft = Draft(text: "um we ship fifteen um builds")
        draft.remove(at: 0, by: .fillers)
        draft.replace(at: 3, with: "15", by: .numberForms)
        draft.remove(at: 4, by: .fillers)
        draft.insert(",", at: 2, by: .spokenPunctuation)
        return draft
    }

    @Test("names every word each step took out, in the order they were said")
    func removals() {
        let record = CleaningRecord(draft: draft(), ran: CleaningSteps.offered.map(\.id))
        let fillers = record.changes.first { $0.step == .fillers }
        #expect(fillers?.removed == ["um", "um"])
        #expect(record.switchedOff.isEmpty)
    }

    @Test("keeps what a rewrite read before, and what a step put in")
    func rewritesAndInsertions() {
        let record = CleaningRecord(draft: draft(), ran: CleaningSteps.offered.map(\.id))
        let numbers = record.changes.first { $0.step == .numberForms }
        #expect(numbers?.replaced == [CleaningRecord.Rewrite(from: "fifteen", to: "15")])
        #expect(record.changes.first { $0.step == .spokenPunctuation }?.inserted == [","])
    }

    @Test("a word a later step rewrote again is still credited to the step that got there first")
    func chainedRewrites() {
        var draft = Draft(text: "dont ship it")
        draft.replace(at: 0, with: "don't", by: .contractions)
        draft.replace(at: 0, with: "Don't", by: .firstWord)
        let record = CleaningRecord(draft: draft, ran: CleaningSteps.offered.map(\.id))
        #expect(
            record.changes.first { $0.step == .contractions }?.replaced
                == [CleaningRecord.Rewrite(from: "dont", to: "don't")])
        #expect(
            record.changes.first { $0.step == .firstWord }?.replaced
                == [CleaningRecord.Rewrite(from: "don't", to: "Don't")])
    }

    @Test("orders the steps by the first word each one reached")
    func orderOfSteps() {
        let record = CleaningRecord(draft: draft(), ran: CleaningSteps.offered.map(\.id))
        #expect(record.changes.map(\.step) == [.fillers, .spokenPunctuation, .numberForms])
    }

    @Test("a draft nothing touched has nothing to report")
    func nothingHappened() {
        let record = CleaningRecord(draft: Draft(text: "we ship on Friday"), ran: [.fillers])
        #expect(record.changes.isEmpty)
        #expect(CleaningRecord(changes: []).isEmpty)
    }

    /// A step that is off is why a word the user expected to go is still there.
    @Test("names the steps that were not in the pipeline that ran")
    func switchedOff() {
        let ran = CleaningSteps.offered.map(\.id).filter { $0 != .fillers }
        let record = CleaningRecord(draft: draft(), ran: ran)
        #expect(record.switchedOff == [.fillers])
        #expect(!record.isEmpty)
    }

    @Test("lists no more words per step than it promises, however long the dictation")
    func bounded() {
        var draft = Draft(text: String(repeating: "um ", count: 40))
        for index in draft.words.indices { draft.remove(at: index, by: .fillers) }
        let record = CleaningRecord(draft: draft, ran: [PassID.fillers])
        #expect(record.changes.first?.removed.count == CleaningRecord.wordLimit)
    }

    @Test("counts every word a step touched, past the words it lists")
    func exactCountsPastTheLimit() {
        var draft = Draft(text: String(repeating: "one ", count: 60))
        for index in 0..<20 { draft.remove(at: index, by: .fillers) }
        for index in 20..<35 { draft.replace(at: index, with: "1", by: .numberForms) }
        for index in stride(from: 59, to: 43, by: -1) {
            draft.insert(",", at: index, by: .spokenPunctuation)
        }
        let record = CleaningRecord(draft: draft, ran: [PassID.fillers])
        let fillers = record.changes.first { $0.step == .fillers }
        let numbers = record.changes.first { $0.step == .numberForms }
        let commas = record.changes.first { $0.step == .spokenPunctuation }
        #expect(fillers?.removedCount == 20)
        #expect(fillers?.removed.count == CleaningRecord.wordLimit)
        #expect(numbers?.replacedCount == 15)
        #expect(numbers?.replaced.count == CleaningRecord.wordLimit)
        #expect(commas?.insertedCount == 16)
        #expect(commas?.inserted.count == CleaningRecord.wordLimit)
    }

    @Test("a count that is left out or too small is read off the list")
    func countsFallBackToTheList() {
        let change = CleaningRecord.Change(
            step: .fillers, removed: ["um", "uh"], replaced: [.init(from: "a", to: "b")],
            inserted: [","], removedCount: 1)
        #expect(change.removedCount == 2)
        #expect(change.replacedCount == 1)
        #expect(change.insertedCount == 1)
        #expect(!CleaningRecord.Change(step: .fillers, removedCount: 3).isEmpty)
    }

    @Test("a dictation done in pieces reports one account, step by step")
    func merging() {
        var first = Draft(text: "um yes")
        first.remove(at: 0, by: .fillers)
        var second = Draft(text: "uh no")
        second.remove(at: 0, by: .fillers)
        second.replace(at: 1, with: "No", by: .firstWord)

        let merged = CleaningRecord.merging([
            CleaningRecord(draft: first, ran: CleaningSteps.offered.map(\.id)),
            CleaningRecord(draft: second, ran: CleaningSteps.offered.map(\.id).dropLast()),
        ])
        #expect(merged.changes.first { $0.step == .fillers }?.removed == ["um", "uh"])
        #expect(merged.changes.map(\.step) == [.fillers, .firstWord])
        #expect(merged.switchedOff == [.spacing])
        #expect(CleaningRecord.merging([]).isEmpty)
    }

    @Test("a merged account is bounded exactly as one piece's is")
    func mergingIsBounded() {
        var piece = Draft(text: String(repeating: "um ", count: 10))
        for index in piece.words.indices { piece.remove(at: index, by: .fillers) }
        let record = CleaningRecord(draft: piece, ran: [PassID.fillers])
        let merged = CleaningRecord.merging([record, record, record])
        #expect(merged.changes.first?.removed.count == CleaningRecord.wordLimit)
        #expect(merged.changes.first?.removedCount == 30)
    }

    @Test("a merged account adds up each piece's full counts, not its listed words")
    func mergingSumsFullCounts() {
        var piece = Draft(text: String(repeating: "um ", count: 14) + "yes")
        for index in 0..<14 { piece.remove(at: index, by: .fillers) }
        piece.replace(at: 14, with: "Yes", by: .firstWord)
        let record = CleaningRecord(draft: piece, ran: [PassID.fillers])
        let merged = CleaningRecord.merging([record, record])
        #expect(merged.changes.first { $0.step == .fillers }?.removedCount == 28)
        #expect(merged.changes.first { $0.step == .firstWord }?.replacedCount == 2)
    }

    @Test("a word a step put in and then took out is named by what it reads as")
    func removedInsertion() {
        var draft = Draft(text: "yes")
        draft.insert(",", at: 0, by: .spokenPunctuation)
        draft.remove(at: 0, by: .spacing)
        let record = CleaningRecord(draft: draft, ran: [PassID.spacing])
        #expect(record.changes.first { $0.step == .spacing }?.removed == [","])
    }

    @Test("a change with nothing in it says so")
    func emptyChange() {
        #expect(CleaningRecord.Change(step: .fillers).isEmpty)
        #expect(!CleaningRecord.Change(step: .fillers, removed: ["um"]).isEmpty)
        #expect(CleaningRecord.Change(step: .fillers).id == .fillers)
    }

    @Test("a recorder with nowhere to put it takes it without complaint")
    func noOpRecorder() async {
        await NoOpCleaningRecorder().record(CleaningRecord(changes: []))
    }
}
