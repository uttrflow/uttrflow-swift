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
        try KeyCommand.run(heard, in: destination, isSecure: target.isSecure, through: poster)
        return "Pressed the key."
    }
}
