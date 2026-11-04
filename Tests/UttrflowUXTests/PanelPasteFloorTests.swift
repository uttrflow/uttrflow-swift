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

    @Test("the report claims a copy only when one was made")
    func reportIsTrue() {
        #expect(
            PanelPasteReport.after(PanelPasteFloor.result(copied: true))
                == PanelPasteReport.after(.textRefused))
        #expect(PanelPasteFloor.result(copied: false) == .textCouldNotPaste)
    }
}
