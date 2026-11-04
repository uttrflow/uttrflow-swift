import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #7919: a one-letter subcommand before a short option is not spelled letters joined with the option.
@Suite("A terminal keeps a one-letter subcommand apart from its option", .bug(id: 7919))
struct InstallShorthandFlagTests {
    private static let terminal = AppContext(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")

    private static func cleaned(_ spoken: String) -> String {
        let situation = SituationResolver.resolve(from: terminal)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "the letter and the option stay two tokens",
        arguments: [
            ("npm i dash g typescript", "npm i -g typescript"),
            ("npm i dash d vitest", "npm i -d vitest"),
            ("yarn i dash g serve", "yarn i -g serve"),
            ("brew i dash g foo", "brew i -g foo"),
            ("npm x dash g typescript", "npm x -g typescript"),
            ("npm install dash g typescript", "npm install -g typescript"),
        ])
    func letterBeforeOption(spoken: String, expected: String) {
        let result = Self.cleaned(spoken)
        #expect(result == expected, "\(result)")
    }
}
