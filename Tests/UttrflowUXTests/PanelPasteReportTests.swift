// Tests for what the user is told after a panel paste, once the panel has gone.
import Testing
import UttrflowCore

@testable import UttrflowUX

/// "I picked a clip and nothing happened" is the failure a clipboard panel has to explain.
@Suite("What a panel paste says after the panel has closed")
struct PanelPasteReportTests {
    @Test(
        "a successful text insertion stays silent",
        arguments: [
            InsertionArrival.confirmed, .notReported,
        ])
    func silent(_ arrival: InsertionArrival) {
        for method in [TextInsertionMethod.accessibility, .pasteboard, .typed] {
            #expect(PanelPasteReport.after(.text(InsertionAttempt(method, arrival: arrival))) == nil)
        }
    }

    @Test("a paste that could not be confirmed stays silent")
    func unconfirmed() {
        #expect(
            PanelPasteReport.after(.text(InsertionAttempt(.pasteboard, arrival: .unconfirmed))) == nil)
    }

    @Test("text left on the clipboard, or refused outright, says to press ⌘V")
    func copied() {
        let leftOnClipboard = PanelPasteReport.after(.text(InsertionAttempt(.clipboard)))
        #expect(leftOnClipboard == PanelPasteReport.copied)
        #expect(PanelPasteReport.after(.textRefused) == PanelPasteReport.copied)
        #expect(PanelPasteReport.copied.primaryLine == "Copied — press ⌘V")
    }

    @Test(
        "an explicit Copy of text or a picture says it was copied",
        arguments: [
            PanelCopyContent.text, .picture,
        ])
    func explicitCopy(_ content: PanelCopyContent) throws {
        let report = try #require(PanelPasteReport.after(.copied(content)))
        #expect(report == PanelPasteReport.copied)
        #expect(report.primaryLine == "Copied — press ⌘V")
        #expect(report.spoken == "Copied to the clipboard, not pasted. Press Command V to paste it.")
    }

    @Test("an explicit Copy of a secret confirms it without exposing its contents")
    func explicitHiddenCopy() throws {
        let report = try #require(PanelPasteReport.after(.copied(.hiddenText)))
        #expect(report.primaryLine == "Copied hidden clip — press ⌘V")
        #expect(
            report.spoken == "Copied a hidden clip to the clipboard, not pasted. Press Command V to paste it."
        )
    }

    @Test("a refused clipboard-free paste does not claim the clip was copied")
    func textCouldNotPaste() throws {
        let report = try #require(PanelPasteReport.after(.textCouldNotPaste))
        #expect(report.primaryLine == "Couldn't paste this clip")
        #expect(report.spoken.contains("clipboard was left unchanged"))
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
            .text(InsertionAttempt(.clipboard)), .textRefused, .pictureRefused, .textCouldNotPaste,
        ]
        for result in recoverable {
            let spoken = PanelPasteReport.after(result)?.spoken
            #expect(spoken?.contains("Command V") == (result != .textCouldNotPaste))
            #expect(spoken?.contains("⌘") == false)
        }
        #expect(PanelPasteReport.after(.pictureMissing)?.spoken.contains("⌘") == false)
    }
}
