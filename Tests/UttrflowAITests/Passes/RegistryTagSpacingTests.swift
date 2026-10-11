import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Registry tags in technical destinations")
struct RegistryTagSpacingTests {
    private func written(_ text: String, in destination: Destination) -> String {
        CleaningPipeline.piece(numbers: .always, digits: .none, destination: destination)
            .run(Draft(text: text)).text
    }

    @Test(
        "a registry image keeps its version after the colon",
        arguments: [
            ("registry.example.com/api: 1.4.2", "registry.example.com/api:1.4.2"),
            ("registry.example.org/team/api: 2.0", "registry.example.org/team/api:2.0"),
            ("registry.example.com:5000/tools: v3.1", "registry.example.com:5000/tools:v3.1"),
        ])
    func registryVersionJoins(input: String, expected: String) {
        #expect(written("image " + input, in: .codeEditor) == "image " + expected)
    }

    @Test("a joined registry tag is idempotent", arguments: [Destination.codeEditor])
    func registryVersionIsIdempotent(destination: Destination) {
        let first = written("image registry.example.com/api: 1.4.2", in: destination)
        #expect(written(first, in: destination) == first)
    }

    @Test(
        "prose and unrecognised tag values keep their colon spacing",
        arguments: [
            "replicas: 3", "image: registry.example.com/api:1.4.2",
            "registry.example.com/api: version 1.4.2", "registry.example.com/api: latest",
            "~/projects/app: 1.4.2", "example.com: 1.4.2",
        ])
    func leavesNonTags(text: String) {
        #expect(written(text, in: .codeEditor) == text)
    }

    @Test(
        "other destinations preserve a path followed by a colon",
        arguments: [Destination.plain, .document, .email])
    func leavesOtherDestinations(destination: Destination) {
        let text = "registry.example.com/api: 1.4.2"
        #expect(written(text, in: destination) == text)
    }
}
