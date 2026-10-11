// Tests that a dictation report masks by default and shares exactly the lines it previews.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowHistory

/// A record holding an email address, a card-like number and a credential.
private func sensitive() -> DictationRecord {
    DictationRecord(
        text:
            "Mail ana@example.com card 4111 1111 1111 1111 key Zx9kLmQ2-rT7p-Wq4N-b8Vc-3Hj6Fd1Sa0Ge thanks Priyamvada",
        when: Date(timeIntervalSince1970: 1_700_000_000),
        applicationIdentifier: "com.example.notes", isFlagged: true, flagReason: .meaningChanging,
        cleanedBy: .rules)
}

@Suite("Dictation report")
struct DictationReportTests {
    @Test("masks an email address, a card-like number and a secret by default")
    func masksSensitiveSpans() {
        let text = DictationReport(record: sensitive()).text
        #expect(!text.contains("ana@example.com"))
        #expect(!text.contains("1111"))
        #expect(!text.contains("Zx9kLmQ2"))
        #expect(text.contains("Text: Mail [email] card [number] key [secret] thanks Priyamvada"))
    }

    @Test("masks a personal dictionary name as a whole word, in any case")
    func masksDictionaryNames() {
        let text = DictationReport(record: sensitive(), names: ["priyamvada"]).text
        #expect(text.contains("thanks [name]"))
    }

    @Test("leaves short numbers and ordinary words alone")
    func keepsOrdinaryText() {
        let record = DictationRecord(text: "Meet at 10 30 on day 5", when: .distantPast)
        #expect(DictationReport(record: record).text.contains("Text: Meet at 10 30 on day 5"))
    }

    @Test("states that the audio is never included and names the error class")
    func statesProvenance() {
        let lines = DictationReport(record: sensitive()).lines
        #expect(lines.contains("Audio: never included"))
        #expect(lines.contains("Error class: meaningChanging"))
        #expect(lines.contains("Cleaned by: rules"))
    }

    @Test("lists the app version, each cleaning stage and the guard refusals without any word")
    func tracesStages() {
        let record = DictationRecord(
            text: "hello", when: .distantPast,
            changeLedger: [
                ChangeLedgerEntry(writtenIndex: 0, pass: .fillers, kind: .removed),
                ChangeLedgerEntry(writtenIndex: 1, pass: .contractions, kind: .replaced, evidence: .single),
            ],
            guardRefusals: [.lostWord, .movedWord])
        let lines = DictationReport(record: record, appVersion: "1.2.3").lines
        #expect(lines.contains("Uttrflow version: 1.2.3"))
        #expect(lines.contains("Stage: fillers removed"))
        #expect(lines.contains("Stage: contractions replaced (single)"))
        #expect(lines.contains("Refused by guard: lostWord, movedWord"))
        #expect(DictationReport(record: record).lines.contains("Uttrflow version: unrecorded"))
    }

    @Test("the shared bytes equal the previewed lines after an edit and a removal")
    func previewEqualsBytes() {
        var report = DictationReport(record: sensitive())
        report.replaceLine(at: 4, with: "Application: withheld")
        report.removeLine(at: 5)
        report.removeLine(at: 99)
        let previewed = report.lines.map { $0 + "\n" }.joined()
        #expect(report.bytes == Data(previewed.utf8))
        #expect(!report.text.contains("com.example.notes"))
        #expect(!report.text.contains("Error class"))
    }
}
