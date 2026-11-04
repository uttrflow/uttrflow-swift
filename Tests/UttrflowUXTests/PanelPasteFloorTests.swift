import Testing
import UttrflowCore
import UttrflowUX

@Suite("What a refused paste leaves behind")
struct PanelPasteFloorTests {
    @Test(
        "a route that stopped before reaching the clipboard still keeps the words",
        arguments: [
            TextInsertionError.insertionTargetChanged, .insertionFieldClosed, .noFocusedTextField,
            .accessibilityDenied, .clipboardUnavailable,
        ])
    func keeps(_ failure: TextInsertionError) {
        #expect(PanelPasteFloor.keepsOnClipboard(after: failure))
    }

    @Test("a newer copy and a cancel are left alone")
    func leavesAlone() {
        #expect(!PanelPasteFloor.keepsOnClipboard(after: TextInsertionError.clipboardChanged))
        #expect(!PanelPasteFloor.keepsOnClipboard(after: TextInsertionError.insertionCancelled))
    }

    @Test("a refusal runs the copy and reports it")
    @MainActor func copies() async {
        var runs = 0
        let result = await PanelPasteFloor.result(after: TextInsertionError.insertionTargetChanged) {
            runs += 1
            return true
        }
        #expect(runs == 1)
        #expect(result == .textRefused)
    }

    @Test("a copy that fails is reported as no copy")
    @MainActor func copyFails() async {
        let result = await PanelPasteFloor.result(after: TextInsertionError.noFocusedTextField) { false }
        #expect(result == .textCouldNotPaste)
    }

    @Test("a newer copy is never overwritten by the copy step")
    @MainActor func newerCopySkips() async {
        var runs = 0
        let kept = await PanelPasteFloor.keep(after: TextInsertionError.clipboardChanged) {
            runs += 1
            return true
        }
        #expect(!kept)
        #expect(runs == 0)
    }

    @Test("the report claims a copy only when one was made")
    func reportIsTrue() {
        #expect(
            PanelPasteReport.after(PanelPasteFloor.result(copied: true))
                == PanelPasteReport.after(.textRefused))
        #expect(PanelPasteFloor.result(copied: false) == .textCouldNotPaste)
    }
}
