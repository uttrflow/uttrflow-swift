import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Registry versions preserve mapping roles")
struct RegistryMappingRoleTests {
    private func written(_ text: String) -> String {
        CleaningPipeline.piece(numbers: .always, digits: .none, destination: .codeEditor)
            .run(Draft(keepingLineBreaks: text)).text
    }

    @Test(
        "mapping keys and literal values retain their separator",
        arguments: [
            "registry.example.com/api: 1.4.2",
            "image registry.example.com/api: 1.4.2",
            "- registry.example.com/api: 1.4.2",
            "outer:\nregistry.example.com/api: 1.4.2",
            "outer:\n- registry.example.com/api: 1.4.2",
            "registry.example.org/team/api: 2.0",
            #"note: "registry.example.com/api: 1.4.2""#,
            #"note: "prefix: registry.example.com/api: 1.4.2 suffix""#,
            #"note: "prefix label\": registry.example.com/api: 1.4.2 suffix""#,
            "note: 'prefix: registry.example.com/api: 1.4.2 suffix'",
            "note: 'prefix: registry.example.com/api: 1.4.2 suffix\"",
            "note: [key: registry.example.com/api: 1.4.2]",
            "note: [key: registry.example.com/api: 1.4.2}",
            "note: (key: registry.example.com/api: 1.4.2)",
        ])
    func preservesMappingRole(input: String) {
        #expect(written(input) == input)
    }

    @Test(
        "a registry version follows a same-line mapping value",
        arguments: [
            ("image: registry.example.com/api: 1.4.2", "image: registry.example.com/api:1.4.2"),
            ("artifact: registry.example.org/team/api: 2.0", "artifact: registry.example.org/team/api:2.0"),
            ("build: registry.example.com:5000/tools: v3.1", "build: registry.example.com:5000/tools:v3.1"),
            (#""image": registry.example.com/api: 1.4.2"#, #""image": registry.example.com/api:1.4.2"#),
        ])
    func preservesMappingValue(input: String, expected: String) {
        #expect(written(input) == expected)
        #expect(written(expected) == expected)
    }

    @Test(
        "known prose, comments and string values retain literal colon spacing",
        arguments: [
            ("README.md", "", CaretStructure.Region.prose),
            ("main.swift", "// ", CaretStructure.Region.comment),
            ("main.swift", "let value = \"", CaretStructure.Region.string),
            ("index.html", "<span data-value=\"", CaretStructure.Region.unrecognised),
            ("index.html", "<p>", CaretStructure.Region.unrecognised),
        ])
    func preservesCaretLiteral(document: String, preceding: String, region: CaretStructure.Region) {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: document,
            precedingText: preceding)
        let situation = SituationResolver.resolve(from: app)
        #expect(situation.intent.region == region)
        let text = "image: registry.example.com/api: 1.4.2"
        let pipeline = CleaningPipeline.piece(
            numbers: .always, digits: .none, insertionPoint: situation.insertion,
            destination: .codeEditor, intent: situation.intent)
        #expect(pipeline.run(Draft(text: text)).text == text)
    }
}
