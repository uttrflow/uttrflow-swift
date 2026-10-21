import Testing
import UttrflowCore

@testable import UttrflowAI

/// A command line takes the recogniser's pause marks off, so a doubled word they hid is a stammer on the first run too.
@Suite("A terminal cuts a stammer its pause marks hid", .bug(id: 7327))
struct TerminalStammerTests {
    private static func pipeline(steps: CleaningSteps = .default) -> CleaningPipeline {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .terminal)
        return CleaningPipeline.standard(for: .standard(for: .terminal), situation: situation, steps: steps)
    }

    @Test(
        "the doubled word is cut once, and cleaning the result again changes nothing",
        arguments: [
            ("my my!", "my"),
            ("we? we", "we"),
            ("is?! is", "is"),
            ("their! their 42", "their 42"),
        ])
    func cutOnFirstRun(spoken: String, expected: String) {
        let once = Self.pipeline().run(Draft(text: spoken)).text
        #expect(once == expected)
        #expect(Self.pipeline().run(Draft(text: once)).text == once)
    }

    @Test("with stammers switched off, the doubled word stays")
    func stammersOff() {
        let steps = CleaningSteps(switchedOff: [.stammers])
        #expect(Self.pipeline(steps: steps).run(Draft(text: "my my!")).text == "my my")
    }
}
