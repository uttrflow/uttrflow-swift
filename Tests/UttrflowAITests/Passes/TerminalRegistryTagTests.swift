import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Literal registry tag separators")
struct TerminalRegistryTagTests {
    private static let images = [
        "image registry.example.com/api: 1.4.2",
        "image registry.example.com/team/api: 1.4.2",
        "image registry.example.com:5000/team/api: v1.4.2",
        "image localhost:5000/api: V1.4.2",
    ]

    @Test("keeps a host-qualified image tag colon through piece cleaning", arguments: Self.images)
    func keepsRegistryColon(input: String) {
        #expect(NotationInput.settled(Draft(text: input), by: .codeEditorCommands).text == input)
        let pipeline = CleaningPipeline.piece(numbers: .always, digits: .none, destination: .terminal)
        #expect(pipeline.run(Draft(text: input)).text == input)
    }

    @Test("keeps the equivalent code-editor input unchanged", arguments: Self.images)
    func codeEditorControl(input: String) {
        let pipeline = CleaningPipeline.piece(numbers: .always, digits: .none, destination: .codeEditor)
        #expect(pipeline.run(Draft(text: input)).text == input)
    }

    @Test(
        "ordinary pause marks still settle when a registry version does not follow",
        arguments: [
            ("note: 1.4.2", "note 1.4.2"),
            ("src/api: 1.4.2", "src/api 1.4.2"),
            ("registry.example.com/api: retry", "registry.example.com/api retry"),
            ("registry.example.com/api; 1.4.2", "registry.example.com/api 1.4.2"),
        ]
    )
    func ordinaryPauses(input: String, expected: String) {
        #expect(NotationInput.settled(Draft(text: input), by: .codeEditorCommands).text == expected)
    }
}
