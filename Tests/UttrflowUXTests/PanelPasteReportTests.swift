// Tests for what the user is told after a panel paste, once the panel has gone.
import Testing
import UttrflowCore

@testable import UttrflowUX

/// "I picked a clip and nothing happened" is the failure a clipboard panel has to explain.
@Suite("What a panel paste says after the panel has closed")
struct PanelPasteReportTests {
    @Test(
        "a paste seen to arrive, or one the target cannot report, stays silent",
        arguments: [
            InsertionArrival.confirmed, .notReported,
        ])
    func silent(_ arrival: InsertionArrival) {
        for method in [TextInsertionMethod.accessibility, .pasteboard, .typed] {
            #expect(PanelPasteReport.after(.text(InsertionAttempt(method, arrival: arrival))) == nil)
        }
    }

    @Test("a paste that was never seen to arrive says so in the dictation's words")
    func unconfirmed() throws {
        let report = try #require(
            PanelPasteReport.after(.text(InsertionAttempt(.pasteboard, arrival: .unconfirmed))))
        #expect(report.primaryLine == "Inserted — not confirmed")
        #expect(report.secondaryLine?.contains("⌘V") == true)
        #expect(report.spoken.contains("Command V"))
    }

    @Test("text left on the clipboard, or refused outright, says to press ⌘V")
    func copied() {
        let leftOnClipboard = PanelPasteReport.after(.text(InsertionAttempt(.clipboard)))
        #expect(leftOnClipboard == PanelPasteReport.copied)
        #expect(PanelPasteReport.after(.textRefused) == PanelPasteReport.copied)
        #expect(PanelPasteReport.copied.primaryLine == "Copied — press ⌘V")
    }

    @Test("a picture whose paste was refused says the same as text, since it is on the clipboard too")
    func pictureRefused() {
        #expect(PanelPasteReport.after(.pictureRefused) == PanelPasteReport.copied)
    }

    @Test("a picture that has gone says so, in the panel's own words for it")
    func pictureMissing() throws {
        let report = try #require(PanelPasteReport.after(.pictureMissing))
        guard case .say(let notice) = PanelOutcome.pictureMissing(PanelFixture.clip("")).effect else {
            Issue.record("a missing picture should say something on the panel")
            return
        }
        #expect(report.primaryLine == notice.message)
        #expect(report.symbolName == notice.symbolName)
    }

    @Test("every sentence is spoken with the key spelled out, never as a symbol")
    func spokenWithoutSymbols() {
        let recoverable: [PanelPasteResult] = [
            .text(InsertionAttempt(.pasteboard, arrival: .unconfirmed)),
            .text(InsertionAttempt(.clipboard)), .textRefused, .pictureRefused,
        ]
        for result in recoverable {
            let spoken = PanelPasteReport.after(result)?.spoken
            #expect(spoken?.contains("Command V") == true)
            #expect(spoken?.contains("⌘") == false)
        }
        #expect(PanelPasteReport.after(.pictureMissing)?.spoken.contains("⌘") == false)
    }
}
