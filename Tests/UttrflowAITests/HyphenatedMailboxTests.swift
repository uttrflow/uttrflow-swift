import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #7924: a mailbox joined by a spoken dash or hyphen is written as an address when it is announced.
@Suite("A hyphenated mailbox is written as an address", .bug(id: 7924))
struct HyphenatedMailboxTests {
    private static let terminal = AppContext(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
    private static let notes = AppContext(applicationName: "Notes", bundleIdentifier: "com.apple.Notes")

    private static func cleaned(_ spoken: String, into app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "an announced mailbox with a dash or hyphen keeps the mark and the at sign",
        arguments: [
            ("send it to no dash reply at example dot com", "send it to no-reply@example.com"),
            ("email no hyphen reply at example dot com", "email no-reply@example.com"),
            ("send it to team plus ops at example dot com", "send it to team+ops@example.com"),
        ])
    func announced(spoken: String, written: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == written)
        #expect(Self.cleaned(spoken, into: Self.notes).contains(written.dropFirst()))
    }
}
