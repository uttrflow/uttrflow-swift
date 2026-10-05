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

    override func paste(_ sender: Any?) {
        apply(NSPasteboard.general.string(forType: .string) ?? "", by: .keys)
    }

    override func insertNewline(_ sender: Any?) {
        if !singleLine { apply("\n", by: .keys) }
    }

    /// Replaces the selection with `text` as the mode allows, and moves the caret to the end of what landed.
    private func apply(_ text: String, by route: FixtureRoute) {
        guard let edit = mode.edit(string, replacing: selectedRange(), with: text, by: route) else { return }
        unmarkText()
        string = edit.text
        setSelectedRange(NSRange(location: edit.caret, length: 0))
        onChange()
    }
}
