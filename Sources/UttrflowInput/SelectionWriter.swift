// Replaces a field's selection through its Accessibility attributes, checking each step.
import ApplicationServices
import Foundation
import UttrflowCore

/// The four Accessibility attributes a selection is read and written through; the real one wraps an `AXUIElement`.
protocol SelectionAttributes: Sendable {
    /// The field's whole contents, when it will say.
    func value() -> String?
    /// The selection in UTF-16 units, when the field will say.
    func selectedRange() -> CFRange?
    /// Writes over the selection, or at the caret when there is none.
    func setSelectedText(_ text: String) -> AXError
    /// Moves the selection.
    func setSelectedRange(_ range: CFRange) -> AXError
}

/// Writes into one focused field through its attributes, so the order of the steps is testable without a window.
struct SelectionWriter<Field: SelectionAttributes>: FocusedTextField {
    /// The field this writes into.
    let field: Field
    /// Extra times the value is re-read before "did not change" is believed, catching a value republished a moment late (#601).
    var lateWriteRereads = 2
    /// How long to wait before each re-read.
    var lateWriteInterval = Duration.milliseconds(20)
    /// Pauses between re-reads; a test overrides this to skip the wait.
    var sleep: @Sendable (Duration) -> Void = SelectionWriter.threadSleep

    func replaceSelection(with text: String) throws(TextInsertionError) {
        // Read first so the write can be checked; a field that will not answer is trusted.
        let before = field.value()
        let selectionBefore = field.selectedRange()

        let result = field.setSelectedText(text)
        guard result == .success else {
            throw .insertionRejected(description: "the field refused the text (\(result.rawValue))")
        }

        // The selection collapsing to where this text ends is a write, even where the text it replaced reads the same.
        if let selectionBefore, let after = field.selectedRange(), after.length == 0,
            after.location == selectionBefore.location + text.utf16.count
        {
            return
        }

        // A success that changed nothing is the failure this catches, once a moment late still shows nothing. See `Docs/insertion.md`.
        guard let before, !text.isEmpty, stillUnchanged(from: before) else { return }
        throw .insertionRejected(description: "the field accepted the text and did not change")
    }

    /// Re-reads the value a few times, since a write forwarded to another process can republish it late rather than never.
    private func stillUnchanged(from before: String) -> Bool {
        var rereadsLeft = lateWriteRereads
        while true {
            guard let after = field.value(), after == before else { return false }
            guard rereadsLeft > 0 else { return true }
            sleep(lateWriteInterval)
            rereadsLeft -= 1
        }
    }

    /// Blocks this thread, safe here because the caller is already the synchronous Accessibility write path.
    private static func threadSleep(_ duration: Duration) {
        let parts = duration.components
        Thread.sleep(forTimeInterval: Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }

    /// Grows the selection back over what is replaced first, so one write replaces it and undo sees one edit.
    func replaceSelection(
        replacing replaced: String, with text: String
    ) throws(TextInsertionError) {
        guard !replaced.isEmpty else { return try replaceSelection(with: text) }
        let caret = try selectBackwards(over: replaced)
        do {
            try replaceSelection(with: text)
        } catch {
            // A field that takes the selection and refuses the text keeps its caret, not a selection.
            _ = try? select(caret)
            throw error
        }
    }

    /// Moves the selection's start back over `replaced`, once it is confirmed to be there, and answers with the selection it replaces.
    private func selectBackwards(over replaced: String) throws(TextInsertionError) -> CFRange {
        guard let whole = field.value(), let selection = field.selectedRange() else {
            throw .insertionRejected(description: "the field will not report its selection")
        }
        guard
            let widened = BackwardSelection.replacing(
                in: whole, location: selection.location, length: selection.length,
                covering: replaced.count)
        else {
            throw .insertionRejected(description: "the field has too little text before the caret")
        }
        // Checked like the typed route, so a character typed since the edit was worked out is never taken back.
        guard BackwardSelection.confirms(replaced, in: whole, endingAt: selection.location) else {
            throw .insertionRejected(description: "the text before the caret is not what would be replaced")
        }
        try select(CFRange(location: widened.lowerBound, length: widened.count))
        return selection
    }

    /// Sets the selection, which a field that hides its range refuses.
    private func select(_ range: CFRange) throws(TextInsertionError) {
        let result = field.setSelectedRange(range)
        guard result == .success else {
            throw .insertionRejected(
                description: "the field refused the selection (\(result.rawValue))")
        }
    }
}
