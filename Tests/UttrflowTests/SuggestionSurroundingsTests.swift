import Testing
import UttrflowContext

@testable import Uttrflow

@Suite("Which windows a model pass walks")
struct SuggestionSurroundingsTests {
    @Test("A terminal is not walked, since its value already holds the scrollback")
    func terminalIsNotWalked() {
        let terminal = FocusedFieldSnapshot(
            bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea")
        #expect(!SuggestionCoordinator.walksSurroundings(of: terminal))
    }

    @Test("Any other application is walked")
    func otherApplicationsAreWalked() {
        let notes = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.notes", applicationName: "Notes", role: "AXTextArea")
        #expect(SuggestionCoordinator.walksSurroundings(of: notes))
    }
}
