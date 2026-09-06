public import UttrflowCore

/// Writes straight into the focused field, which leaves the clipboard alone and writes at the caret.
public struct AccessibilityTextInsertionEngine: TextInsertionEngine {
    public let method: TextInsertionMethod = .accessibility

    private let focus: any AccessibilityFocus

    public init(focus: any AccessibilityFocus) {
        self.focus = focus
    }

    public func canInsert() async -> Bool {
        focus.focusedTextField() != nil
    }

    public func insert(_ text: String) async throws(TextInsertionError) {
        guard let field = focus.focusedTextField() else { throw .noFocusedTextField }
        try field.replaceSelection(with: text)
    }
}

extension AccessibilityTextInsertionEngine: CompletionWriting {
    public func canWrite() async -> Bool { await canInsert() }

    /// One write, so the field's own undo sees one edit rather than a delete and a typing run.
    public func write(_ text: String, replacing replaced: String) async throws(TextInsertionError) {
        guard let field = focus.focusedTextField() else { throw .noFocusedTextField }
        try field.replaceSelection(precededBy: replaced.count, with: text)
    }
}
