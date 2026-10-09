import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("Diagnostics: why the last dictation read no screen text")
struct DiagnosticsScreenTextTests {
    @Test(
        "names each reason under Last dictation and in the report",
        arguments: [
            (ContextUnavailableReason.notTrusted, "none (not trusted)"),
            (.noFocusedElement, "none (no focused field)"),
            (.refused, "none (refused)"),
            (.timedOut, "none (timed out)"),
            (.secure, "none (secure)"),
            (.notTextSurface, "none (no text surface)"),
        ])
    func namesTheReason(_ reason: ContextUnavailableReason, detail: String) {
        let snapshot = DiagnosticsSnapshot(screenTextUnavailable: reason)
        let row = DiagnosticsPresenter.page(for: snapshot).cleanUp.first { $0.title == "Screen text" }
        #expect(row?.detail == detail)
        #expect(DiagnosticsPresenter.report(for: snapshot).contains("\nScreen text: \(detail)\n"))
    }

    @Test("shows nothing when the read reached the field, or none was taken")
    func absentWhenTextWasRead() {
        let snapshot = DiagnosticsSnapshot()
        #expect(!DiagnosticsPresenter.page(for: snapshot).cleanUp.contains { $0.title == "Screen text" })
        #expect(!DiagnosticsPresenter.report(for: snapshot).contains("Screen text"))
    }

    @Test("the recorder keeps the last dictation's reason, and a read that reached the text clears it")
    func recorderKeepsTheLast() async {
        let recorder = DiagnosticsRecorder()
        await recorder.recordScreenText(.timedOut)
        #expect(await recorder.screenTextUnavailable == .timedOut)
        await recorder.recordScreenText(nil)
        #expect(await recorder.screenTextUnavailable == nil)
    }
}
