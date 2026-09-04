import AppKit
import UttrflowCore
import UttrflowLocalModel
import UttrflowPipeline

/// The app.
///
/// Deliberately thin: it owns nothing but the objects it wires together, so that
/// everything worth testing lives in a module that a test can reach without a screen.
///
/// It is also the one place the concrete local model is named, so everything below links no MLX.
@main
enum UttrflowApp {
    static func main() {
        let application = NSApplication.shared
        // One model both validates a remembered suggestion and invents one where there is none.
        let model = MLXCandidateScorer(model: .gemma3Small)
        Task.detached { try? await model.prepare() }
        let delegate = AppDelegate(scoring: model, generating: model)
        application.delegate = delegate
        // Regular rather than accessory: Uttrflow has a Dock icon and its window opens at
        // launch, because a product whose whole interface is reachable only through a
        // menu-bar icon is a product most people never see.
        //
        // The reason it used to be an accessory has not gone away — dictation targets
        // another app, and a window that grabs focus is a window in the way — so it is
        // answered elsewhere now rather than by hiding: `minimisesWhileDictating` gets
        // the window out of the way while the user is speaking, and nothing on the
        // dictation path activates the app.
        application.setActivationPolicy(.regular)
        // A regular app with no main menu loses ⌘C, ⌘V, ⌘A and ⌘Z in every text field,
        // because macOS routes them through the Edit menu.
        application.mainMenu = MainMenu.build()
        application.run()
    }
}
