// "delete that", "select that", "undo that" and "replace X with Y" under the command key, on the last dictation. See `Docs/commands.md`.
private import Synchronization
import UttrflowAI
import UttrflowCore
import UttrflowInput
import UttrflowPipeline

/// The command-key edits that act on what Uttrflow last wrote, located through the insertion ledger.
struct RecordedEditCommand: EditCommand {
    private let editor: RecordedEditor
    /// The replace most recently run, which "replace first" or "replace last" corrects; it lives in memory only.
    private let lastReplace = ReplaceMemory()

    init(ledger: InsertionLedger, history: EditHistory = EditHistory()) {
        editor = RecordedEditor(ledger: ledger, history: history, focus: AXAccessibilityFocus())
    }

    func accepts(_ heard: String) -> Bool {
        RecordedEdit(heard: heard) != nil || ReplaceCommand.request(from: heard) != nil
            || ReplaceCommand.choice(from: heard) != nil
    }

    func run(_ heard: String, on target: AppContext) async throws -> String {
        if let edit = RecordedEdit(heard: heard) {
            return try await editor.run(edit)
        }
        if let choice = ReplaceCommand.choice(from: heard) {
            return try await correct(choice)
        }
        guard let request = ReplaceCommand.request(from: heard) else {
            throw TextInsertionError.insertionRejected(description: "no edit was named")
        }
        let change = try await editor.rewrite(
            { ReplaceCommand.apply(request, to: $0).change }, writing: { $0.text })
        lastReplace.request.withLock { $0 = request }
        return ReplaceCommand.done(matches: change.matches)
    }

    /// Redoes the newest replace with the match the user named, refusing when the newest edit was another.
    private func correct(_ choice: ReplaceChoice) async throws -> String {
        guard let request = lastReplace.request.withLock({ $0 }) else {
            throw TextInsertionError.insertionRejected(description: "there is no replace to correct")
        }
        let change = try await editor.correct(
            { ReplaceCommand.correction(of: request, from: $0, replacedBy: $1, choosing: choice) },
            writing: { $0.text })
        return ReplaceCommand.done(matches: change.matches, choosing: choice)
    }
}

/// The replace most recently run, shared by the copies of a command.
private final class ReplaceMemory: Sendable {
    let request = Mutex<ReplaceRequest?>(nil)
}
