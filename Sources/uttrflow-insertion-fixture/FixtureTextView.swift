// A text view that routes every edit through its `FixtureMode`, so a fault shows on the real Accessibility and key paths.
import AppKit

/// A single-line or multi-line field whose edits pass through one `FixtureMode`.
final class FixtureTextView: NSTextView {
    var mode = FixtureMode.faithful
    var singleLine = false
    var onChange: () -> Void = {}
    /// Runs once, the first time Accessibility asks this field where its selection is.
    var onFirstSelectionRead: (() -> Void)?

    override func accessibilityRole() -> NSAccessibility.Role? {
        singleLine ? .textField : super.accessibilityRole()
    }

    override func accessibilitySelectedTextRange() -> NSRange {
        if let read = onFirstSelectionRead {
            onFirstSelectionRead = nil
            DispatchQueue.main.async { read() }
        }
        return super.accessibilitySelectedTextRange()
    }

    override func setAccessibilitySelectedText(_ text: String?) {
        guard mode == .lateWrite else { return apply(text ?? "", by: .accessibility) }
        DispatchQueue.main.asyncAfter(deadline: .now() + FixtureMode.lateWriteDelay) {
            self.apply(text ?? "", by: .accessibility)
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        apply(text, by: .keys)
    }

    /// True while the text view's own paste runs, so its one edit is taken over by `apply`.
    private var pasting = false

    override func paste(_ sender: Any?) {
        pasting = true
        defer { pasting = false }
        super.paste(sender)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard pasting else {
            return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        }
        apply(replacementString ?? "", by: .keys)
        return false
    }

    override func insertNewline(_ sender: Any?) {
        if !singleLine { apply("\n", by: .keys) }
    }

    /// Replaces the selection with `text` as the mode allows, and moves the caret to the end of what landed.
    private func apply(_ text: String, by route: FixtureRoute) {
        guard let edit = mode.edit(string, replacing: selectedRange(), with: text, by: route) else { return }
        unmarkText()
        restore(edit.text, caret: edit.caret)
    }

    /// Sets the contents and caret as one undoable step, so the fixture's Undo takes back one write whole.
    private func restore(_ text: String, caret: Int) {
        let (before, caretBefore) = (string, selectedRange().location)
        // A group of its own: an Accessibility write arrives with no event, so grouping by event would merge writes.
        let undo = window?.undoManager
        undo?.groupsByEvent = false
        undo?.beginUndoGrouping()
        undo?.registerUndo(withTarget: self) { $0.restore(before, caret: caretBefore) }
        undo?.endUndoGrouping()
        string = text
        setSelectedRange(NSRange(location: caret, length: 0))
        onChange()
    }
}
