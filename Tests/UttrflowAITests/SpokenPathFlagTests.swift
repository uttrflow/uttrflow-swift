import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A flag said after a spoken path", .bug(id: 7922))
struct SpokenPathFlagTests {
    @Test(
        "stays a flag of its own and is not glued to the last path segment",
        arguments: [
            ("cat slash etc slash hosts dash n", "cat /etc/hosts -n"),
            ("ls slash var slash log dash a", "ls /var/log -a"),
            ("grep slash var slash log dash i", "grep /var/log -i"),
            ("cat slash etc slash hosts dash n dash b", "cat /etc/hosts -n -b"),
        ])
    func keepsFlagApart(spoken: String, expected: String) async throws {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .terminal)
        let request = TransformationRequest(
            transcription: .fixture(text: spoken, language: .english), situation: situation)
        let text = try await RuleBasedTransformer().transform(request).text
        #expect(String(text.drop(while: { _ in false }).reversed().drop(while: { $0 == "." }).reversed()) == expected)
    }

    @Test("still joins a dash that continues a segment's name")
    func keepsHyphenatedSegment() async throws {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .terminal)
        let request = TransformationRequest(
            transcription: .fixture(text: "cd slash home slash my dash project", language: .english),
            situation: situation)
        let text = try await RuleBasedTransformer().transform(request).text
        #expect(String(text.drop(while: { _ in false }).reversed().drop(while: { $0 == "." }).reversed()) == "cd /home/my-project")
    }
}
