import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #7903: a one-letter flag said after an underscore name stays a flag.
@Suite("A one-letter flag after an underscore name is not glued to it", .bug(id: 7903))
struct TerminalFlagAfterUnderscoreNameTests {
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
        "a lone letter after dash ends the underscore name in a terminal",
        arguments: [
            ("python dash m pytest dash k test underscore login dash x", "python -m pytest -k test_login -x"),
            ("pytest dash k test underscore login dash v", "pytest -k test_login -v"),
            ("pytest dash k smoke dash x", "pytest -k smoke -x"),
        ])
    func flagAfterName(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test("a dash and a word still join inside an underscore name")
    func wordStillJoins() {
        #expect(Self.cleaned("cd build underscore dir dash old", into: Self.terminal) == "cd build_dir-old")
    }

    @Test("a lone letter before a dot still belongs to the name")
    func letterBeforeDot() {
        #expect(
            Self.cleaned("open build underscore file dash x dot txt", into: Self.terminal)
                == "open build_file-x.txt")
    }
}
