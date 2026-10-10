// "press enter", "go to the end" and the other key rows said under the command key. See `Docs/commands.md`.
import UttrflowCore
import UttrflowInput
import UttrflowPipeline

/// Posts the key a whole command-key utterance names, where the destination at key-up allows it.
struct KeyEditCommand: EditCommand {
    let overrides: DestinationOverrides
    var poster: any KeyStrokePosting = SystemKeyStrokePoster()

    func accepts(_ heard: String) -> Bool {
        KeyCommand.row(heard: heard) != nil
    }

    func run(_ heard: String, on target: AppContext) async throws -> String {
        let destination = DestinationClassifier.classify(target, overrides: overrides)
        if let row = KeyCommand.row(heard: heard),
            case .refused(let reason) = KeyCommand.plan(row, in: destination, isSecure: target.isSecure)
        {
            throw EditCommandRefusal(userMessage: reason)
        }
        try KeyCommand.run(heard, in: destination, isSecure: target.isSecure, through: poster)
        return "Pressed the key."
    }
}

/// A command that declined to act and changed nothing: its reason is the whole notice, with nothing to paste.
struct EditCommandRefusal: UttrflowFailure {
    let userMessage: String
    var recovery: RecoveryAction? { nil }
    var severity: FailureSeverity { .informational }
}
