import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #8013: spoken dots at a shell prompt are the dot characters, never an ellipsis and never fewer.
@Suite("A terminal writes three spoken dots as three dots", .bug(id: 8013))
struct TerminalDotsTests {
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
        "dot slash and three dots is the package pattern, and three dots alone are three dot characters",
        arguments: [
            ("go test dot slash dot dot dot", "go test ./..."),
            ("go vet dot slash dot dot dot", "go vet ./..."),
            ("go test dot slash dot dot dot dash v", "go test ./... -v"),
            ("echo wait dot dot dot", "echo wait..."),
        ])
    func threeDots(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test(
        "two dots and a slash are still the parent directory, one dot the current",
        arguments: [
            ("cd dot dot", "cd .."),
            ("ls dot slash scripts", "ls ./scripts"),
        ])
    func otherDotsUnchanged(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test("a recogniser's final stop after the wildcard is taken back, and an ellipsis keeps its dots")
    func finalStopAfterTheWildcard() {
        #expect(Self.cleaned("Go test dot slash dot dot dot.", into: Self.terminal) == "go test ./...")
        #expect(WordShape.withoutTrailingStop("./....") == "./...")
        #expect(WordShape.withoutTrailingStop("wait...") == "wait...")
    }

    @Test("prose still writes three spoken dots as an ellipsis")
    func proseKeepsEllipsis() {
        #expect(Self.cleaned("and then dot dot dot nothing happened", into: Self.notes).contains("\u{2026}"))
    }
}
