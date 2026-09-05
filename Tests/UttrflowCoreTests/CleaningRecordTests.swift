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
