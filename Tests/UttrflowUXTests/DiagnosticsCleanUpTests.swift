import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("Diagnostics says what each clean-up step did")
struct DiagnosticsCleanUpTests {
    /// A dictation the fillers, number and punctuation steps have all been over.
    private func record(switchedOff: [PassID] = []) -> CleaningRecord {
        var draft = Draft(text: "um we ship fifteen um builds")
        draft.remove(at: 0, by: .fillers)
        draft.replace(at: 3, with: "15", by: .numberForms)
        draft.remove(at: 4, by: .fillers)
        return CleaningRecord(
            changes: CleaningRecord(draft: draft, ran: []).changes, switchedOff: switchedOff)
    }

    @Test("names the words a step removed, not just how many")
    func namesTheWords() {
        let page = DiagnosticsFixture.page(cleaning: record())
        let fillers = page.cleanUp.first { $0.title == "Filler words" }
        #expect(fillers?.detail == "removed 2: um, um")
        #expect(fillers?.state == .good)
    }

    @Test("says what a rewrite read before")
    func namesTheRewrite() {
        let page = DiagnosticsFixture.page(cleaning: record())
        #expect(page.cleanUp.first { $0.title == "Numbers" }?.detail == "rewrote 1: fifteen → 15")
    }

    @Test("a step that removed, rewrote and added says all three")
    func everyKindOfChange() {
        let change = CleaningRecord.Change(
            step: .spokenPunctuation, removed: ["comma"],
            replaced: [CleaningRecord.Rewrite(from: "stop", to: ".")], inserted: [","])
        #expect(
            DiagnosticsPresenter.detail(of: change)
                == "removed 1: comma; rewrote 1: stop → .; added 1: ,")
    }

    /// A step that is off is why a word the user expected to go is still there.
    @Test("a step that is switched off is named as off rather than left out")
    func switchedOffIsNamed() {
        let page = DiagnosticsFixture.page(cleaning: record(switchedOff: [.stammers]))
        let row = page.cleanUp.first { $0.title == "Stammers" }
        #expect(row?.detail == "Switched off")
        #expect(row?.state == .unknown)
    }

    @Test("nothing dictated yet is said, not drawn as an empty table")
    func nothingYet() {
        let page = DiagnosticsFixture.page()
        #expect(page.cleanUp.map(\.detail) == ["Nothing dictated yet"])
        #expect(page.cleanUp.first?.state == .unknown)
    }

    @Test("a dictation that needed no tidying says so")
    func nothingToDo() {
        let page = DiagnosticsFixture.page(cleaning: CleaningRecord(changes: []))
        #expect(page.cleanUp.map(\.detail) == ["Nothing needed changing"])
        #expect(page.cleanUp.first?.state == .good)
    }

    /// The page is on the user's own screen; the report is pasted somewhere else.
    @Test("the copied report counts the words rather than quoting them")
    func reportCountsOnly() {
        let report = DiagnosticsPresenter.report(
            for: DiagnosticsSnapshot(cleaning: record(switchedOff: [.stammers])),
            locale: DiagnosticsFixture.locale)
        #expect(report.contains("Clean-up steps, last dictation"))
        #expect(report.contains("Filler words: removed 2"))
        #expect(report.contains("Numbers: rewrote 1"))
        #expect(report.contains("Stammers: switched off"))
        #expect(!report.contains("fifteen"))
    }

    @Test("a report with nothing tidied says nothing about tidying")
    func reportWithNothing() {
        let report = DiagnosticsPresenter.report(
            for: DiagnosticsSnapshot(), locale: DiagnosticsFixture.locale)
        #expect(!report.contains("Clean-up steps"))
    }

    @Test("a step that only added something is counted as an addition")
    func countedAddition() {
        let change = CleaningRecord.Change(step: .spokenPunctuation, inserted: [","])
        let counted = DiagnosticsPresenter.countedCleanUp(CleaningRecord(changes: [change]))
        #expect(counted == ["  Spoken punctuation: added 1"])
    }

    @Test("what the recorder keeps is the last dictation, and only the last")
    func recorderKeepsTheLast() async {
        let recorder = DiagnosticsRecorder()
        #expect(await recorder.lastCleaning == nil)
        await recorder.record(CleaningRecord(changes: [.init(step: .fillers, removed: ["um"])]))
        await recorder.record(CleaningRecord(changes: [.init(step: .fillers, removed: ["uh"])]))
        #expect(await recorder.lastCleaning?.changes.first?.removed == ["uh"])
    }
}
