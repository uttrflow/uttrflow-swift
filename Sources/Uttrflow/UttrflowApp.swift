// The entry point.

import AppKit
import UttrflowCore
import UttrflowLocalModel
import UttrflowPipeline

/// The app, owning nothing but the objects it wires together.
@main
enum UttrflowApp {
    static func main() {
        let application = NSApplication.shared
        // One model both validates a remembered suggestion and invents one where there is none; its weights are fetched when the feature is first built, never at launch.
        let model = MLXCandidateScorer(model: .gemma3)
        let delegate = AppDelegate(
            scoring: model, generating: model, prepareModel: { try? await model.prepare() })
        application.delegate = delegate
        // Regular, not accessory: Uttrflow has a Dock icon and its window opens at launch.
        application.setActivationPolicy(.regular)
        // A regular app with no main menu loses ⌘C, ⌘V, ⌘A and ⌘Z in every text field.
        application.mainMenu = MainMenu.build()
        application.run()
    }
}
