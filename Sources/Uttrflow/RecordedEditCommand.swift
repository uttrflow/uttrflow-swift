// "delete that", "select that", "undo that", "replace X with Y" and the reformats under the command key, on the last dictation. See `Docs/commands.md`.
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

    /// The user's destination choices, which decide at key-up whether a list is laid out where the dictation is.
    private let overrides: DestinationOverrides

    init(ledger: InsertionLedger, overrides: DestinationOverrides, history: EditHistory = EditHistory()) {
        editor = RecordedEditor(ledger: ledger, history: history, focus: AXAccessibilityFocus())
        self.overrides = overrides
    }

    func accepts(_ heard: String) -> Bool {
        RecordedEdit(heard: heard) != nil || ReplaceCommand.request(from: heard) != nil
            || ReplaceCommand.choice(from: heard) != nil || ReformatCommand.reformat(heard: heard) != nil
    }

    func run(_ heard: String, on target: AppContext) async throws -> String {
        if let edit = RecordedEdit(heard: heard) {
            return try await editor.run(edit)
        }
        if let choice = ReplaceCommand.choice(from: heard) {
            return try await correct(choice)
        }
        if let reformat = ReformatCommand.reformat(heard: heard) {
            return try await run(reformat, in: DestinationClassifier.classify(target, overrides: overrides))
        }
        guard let request = ReplaceCommand.request(from: heard) else {
            throw TextInsertionError.insertionRejected(description: "no edit was named")
        }
        let change = try await editor.rewrite(
            { ReplaceCommand.apply(request, to: $0).change }, writing: { $0.text })
        lastReplace.request.withLock { $0 = request }
        return ReplaceCommand.done(matches: change.matches)
    }

    /// Writes the last dictation in the case or layout `reformat` names; a refusal writes nothing and is the notice.
    private func run(_ reformat: Reformat, in destination: Destination) async throws -> String {
        let refusal = Mutex<String?>(nil)
        do {
            try await editor.rewrite { text in
                switch ReformatCommand.plan(reformat, of: text, in: destination) {
                case .reformatted(let written): return written
                case .refused(let reason):
                    refusal.withLock { $0 = reason }
                    return nil
                }
            }
        } catch {
            if let reason = refusal.withLock({ $0 }) { throw EditCommandRefusal(userMessage: reason) }
            throw error
        }
        return ReformatCommand.done(reformat)
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
