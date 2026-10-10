// Headings, emphasis, code and quotes said under the command key, in a Markdown document. See `Docs/commands.md`.
import UttrflowAI
import UttrflowCore
import UttrflowInput
import UttrflowPipeline

/// Writes the edit `MarkdownCommand` plans over the selection read at key-up, and nothing where it plans none.
struct MarkdownEditCommand: EditCommand {
    var focus: any AccessibilityFocus = AXAccessibilityFocus()

    func accepts(_ heard: String) -> Bool {
        MarkdownCommand.row(for: heard) != nil
    }

    func run(_ heard: String, on target: AppContext) async throws -> String {
        guard !target.isSecure, let edit = MarkdownCommand.edit(for: heard, on: target) else {
            throw TextInsertionError.insertionRejected(
                description:
                    "That works only in a Markdown document, on a selection it can mark, so nothing was changed."
            )
        }
        guard let field = focus.focusedTextField() else { throw TextInsertionError.noFocusedTextField }
        try field.replaceSelection(with: edit)
        return "Formatted the selection."
    }
}
