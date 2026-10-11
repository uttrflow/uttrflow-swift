import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("Dictation pipeline: no line break reaches a field whose Return acts")
struct DictationPipelineOutputSafetyTests {
    /// What one rules-tidied dictation of `spoken` writes into the app named by `bundleIdentifier`.
    private func written(_ spoken: String, into name: String, _ bundleIdentifier: String) async -> [String] {
        let scenario = Scenario(
            pieces: [ScriptedPiece(spoken)],
            context: .fixture(applicationName: name, bundleIdentifier: bundleIdentifier))
        return await ScenarioDriver.run(scenario).writes
    }

    @Test(
        "a spoken break in a chat or a terminal arrives as a space",
        arguments: [
            ("Slack", "com.tinyspeck.slackmacgap"), ("Terminal", "com.apple.Terminal"),
        ])
    func spokenBreakBecomesSpace(_ app: (String, String)) async throws {
        for spoken in ["see you soon new line bring snacks", "see you soon new paragraph bring snacks"] {
            let writes = await written(spoken, into: app.0, app.1)
            let text = try #require(writes.first)
            #expect(writes.count == 1)
            #expect(!text.contains("\n"), "\(app.0): \(writes)")
            #expect(text.lowercased().contains("bring snacks"), "\(app.0): \(writes)")
        }
    }

    @Test("a spoken break in a document still arrives as a break")
    func documentKeepsBreak() async throws {
        let writes = await written(
            "see you soon new paragraph bring snacks", into: "TextEdit", "com.apple.TextEdit")
        #expect(try #require(writes.first).contains("\n"), "\(writes)")
    }
}
