// Tests that the copied diagnostics report carries no dictated or personal words, whatever the snapshot holds.
import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("The copied diagnostics report quotes nothing the speaker said")
struct DiagnosticsReportRedactionTests {
    /// Invented words that stand for what the speaker said or keeps; none of them may leave the Mac.
    static let secrets = [
        "zorblaxquent", "quillithmar", "vexonturbid", "plimsorrow", "drennikalt", "fozzlewick",
        "marquelloth", "trivendusk",
    ]

    /// A snapshot whose every text-bearing field is filled with the invented words.
    static func snapshot() -> DiagnosticsSnapshot {
        let change = CleaningRecord.Change(
            step: .fillers, removed: [secrets[0]],
            replaced: [CleaningRecord.Rewrite(from: secrets[1], to: secrets[2])],
            inserted: [secrets[3]])
        let cleaning = CleaningRecord(
            changes: [change], switchedOff: [],
            refusals: [
                CleaningRecord.Refusal(
                    engine: "local", reason: "dropped \(secrets[4])", kind: .lostWord)
            ])
        return DiagnosticsSnapshot(
            vocabularyPrompt: [secrets[5], secrets[6], secrets[7]], cleaning: cleaning,
            tidyTally: tally(), lastCleanedBy: .rules)
    }

    /// A tally whose one skip carries free text that must never be copied out.
    static func tally() -> TidyTally {
        var tally = TidyTally()
        tally.add(
            TidyOutcome(
                finishedBy: .rules,
                record: CleaningRecord(
                    changes: [],
                    refusals: [.init(engine: "localModel", reason: secrets[4], kind: .lostWord)],
                    unavailableEngines: [.init(engine: "foundationModels", reason: .other(secrets[0]))])))
        return tally
    }

    @Test("dictated words, rewrites, refusal reasons and dictionary words are absent")
    func noSecretReachesTheReport() {
        let report = DiagnosticsPresenter.report(
            for: Self.snapshot(), locale: DiagnosticsFixture.locale)
        for secret in Self.secrets {
            #expect(!report.contains(secret), "the copied report quotes \(secret)")
        }
    }

    @Test("the report still counts what the clean-up step did")
    func countsSurvive() {
        let report = DiagnosticsPresenter.report(
            for: Self.snapshot(), locale: DiagnosticsFixture.locale)
        #expect(report.contains("removed 1, rewrote 1, added 1"))
        #expect(report.contains(RefusalKind.lostWord.summary))
        #expect(report.contains("Tidy outcomes, last 1 pieces"))
        #expect(report.contains("  localModel: accepted 0, refused lostWord 1"))
        #expect(report.contains("  foundationModels: accepted 0, skipped other 1"))
        #expect(report.contains("  rules: accepted 1"))
    }

    @Test("forgetting empties the tally")
    func forgetEmptiesTheTally() async {
        let recorder = DiagnosticsRecorder()
        await recorder.record(TidyOutcome(finishedBy: .rules))
        #expect(await recorder.tidyTally.outcomes.count == 1)
        await recorder.forget()
        #expect(await recorder.tidyTally == TidyTally())
    }

    @Test("forgetting empties the read rung tally")
    func forgetEmptiesTheReadRungTally() async {
        let recorder = DiagnosticsRecorder()
        await recorder.recordContextRead(.wholeValue, in: "com.example.editor")
        #expect(await recorder.readRungs.counts == ["com.example.editor": [.wholeValue: 1]])
        await recorder.forget()
        #expect(await recorder.readRungs == ContextReadTally())
    }

    /// Reads in two applications, three answered by the ranged rung and one by the whole value.
    static func readRungs() -> ContextReadTally {
        var tally = ContextReadTally()
        tally.add(.rangedValue, in: "com.example.editor")
        tally.add(.rangedValue, in: "com.example.editor")
        tally.add(.wholeValue, in: "com.example.editor")
        tally.add(.rangedValue, in: "com.example.chat")
        return tally
    }

    @Test("the page counts each application's read rungs by bundle identifier")
    func pageCountsRungsPerApplication() {
        let page = DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot(readRungs: Self.readRungs()), locale: DiagnosticsFixture.locale)
        let rows = page.cleanUp.filter { $0.title.hasPrefix("Screen reads, ") }
        #expect(rows.map(\.title) == ["Screen reads, com.example.chat", "Screen reads, com.example.editor"])
        #expect(rows.map(\.detail) == ["rangedValue 1", "rangedValue 2, wholeValue 1"])
    }

    @Test("the copied report sums read rungs across applications and names none")
    func reportSumsRungsWithoutApplications() {
        let report = DiagnosticsPresenter.report(
            for: DiagnosticsSnapshot(readRungs: Self.readRungs()), locale: DiagnosticsFixture.locale)
        #expect(report.contains("Screen reads by rung, all apps: rangedValue 3, wholeValue 1"))
        #expect(!report.contains("com.example"))
    }
}
