import Testing

@testable import UttrflowAI
import UttrflowCore

/// The "Typed into:" phrase names the place the style block came from, however that place was decided.
@Suite("Issue203ClassSweep")
struct Issue203ClassSweepTests {
    /// The phrase the prompt shows for a situation, without the window title or the selection.
    private func phrase(_ situation: Situation) -> String {
        AppContextDescriber.describe(situation) ?? ""
    }

    /// A web app is classified by its window title and described by its bundle identifier, so the two disagree.
    @Test("the phrase agrees with the block for a web app")
    func browserOnGmail() {
        let app = AppContext(
            applicationName: "Google Chrome", bundleIdentifier: "com.google.Chrome",
            documentName: "Inbox - me@example.com - Gmail")
        let situation = SituationResolver.resolve(from: app)
        #expect(situation.destination == .email)
        #expect(PromptBuilder.standard.block(for: situation.destination).id == "email")
        #expect(!phrase(situation).contains("a web browser"))
    }

    /// The user's own override moves the block and never reaches the line above it.
    @Test("the phrase agrees with the block once the user has overridden it")
    func overrideIgnoredByThePhrase() {
        let app = AppContext(applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        let overrides = DestinationOverrides([
            DestinationOverride(bundleIdentifier: "com.tinyspeck.slackmacgap", destination: .codeEditor)
        ])
        let situation = SituationResolver.resolve(from: app, overrides: overrides)
        #expect(situation.destination == .codeEditor)
        #expect(PromptBuilder.standard.block(for: situation.destination).id == "codeEditor")
        #expect(!phrase(situation).contains("a chat app"))
    }
}
