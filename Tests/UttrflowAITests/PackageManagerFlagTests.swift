import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #7905: a short option after a package manager's "add" is written as the option.
@Suite("A short option after a program's add sub-command is written as the option", .bug(id: 7905))
struct PackageManagerFlagTests {
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
        "yarn add takes a short option as npm install does",
        arguments: [
            ("yarn add dash d typescript", "yarn add -d typescript"),
            ("npm install dash d eslint", "npm install -d eslint"),
        ])
    func terminal(spoken: String, expected: String) {
        let result = Self.cleaned(spoken, into: Self.terminal)
        #expect(result == expected, "\(result)")
    }

    @Test(
        "the same command said in prose keeps its option",
        arguments: [
            ("yarn add dash d typescript", "Yarn add -d TypeScript."),
            ("npm install dash d eslint", "Npm install -d ESLint."),
        ])
    func prose(spoken: String, expected: String) {
        let result = Self.cleaned(spoken, into: Self.notes)
        #expect(result == expected, "\(result)")
    }

    @Test("add with no program before it still names the mark")
    func addNamesTheMark() {
        let result = Self.cleaned("add dash d to the list", into: Self.notes)
        #expect(!result.contains("-d"), "\(result)")
    }
}
