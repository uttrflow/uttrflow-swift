// The entry point.

import AppKit
import UttrflowCore
import UttrflowPipeline

/// The app, owning nothing but the objects it wires together.
@main
enum UttrflowApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // Regular, not accessory: Uttrflow has a Dock icon and its window opens at launch.
        application.setActivationPolicy(.regular)
        // A regular app with no main menu loses ⌘C, ⌘V, ⌘A and ⌘Z in every text field.
        application.mainMenu = MainMenu.build()
        application.run()
    }
}
