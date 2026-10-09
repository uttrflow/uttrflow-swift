// "delete that", "select that", "undo that" and "replace X with Y" under the command key, on the last dictation. See `Docs/commands.md`.
import UttrflowAI
import UttrflowCore
import UttrflowInput
import UttrflowPipeline

/// The command-key edits that act on what Uttrflow last wrote, located through the insertion ledger.
struct RecordedEditCommand: EditCommand {
    private let editor: RecordedEditor

    init(ledger: InsertionLedger, history: EditHistory = EditHistory()) {
        editor = RecordedEditor(ledger: ledger, history: history, focus: AXAccessibilityFocus())
    }

    func accepts(_ heard: String) -> Bool {
        RecordedEdit(heard: heard) != nil || ReplaceCommand.request(from: heard) != nil
    }

    func run(_ heard: String, on target: AppContext) async throws -> String {
        if let edit = RecordedEdit(heard: heard) {
            try await editor.run(edit)
            return edit.done
        }
        guard let request = ReplaceCommand.request(from: heard) else {
            throw TextInsertionError.insertionRejected(description: "no edit was named")
        }
        try await editor.rewrite { ReplaceCommand.apply(request, to: $0).text }
        return "Replaced the words in the last dictation."
    }
}
