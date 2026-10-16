import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken login name and host after a remote command", .bug(id: 7877))
struct SpokenRemoteAddressTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "writes the login name, an at sign and the host after a remote-login program",
        arguments: [
            ("ssh john at example dot com", "ssh john@example.com"),
            ("sftp deploy at files dot example dot org", "sftp deploy@files.example.org"),
        ]
    )
    func writesRemoteTargets(input: String, expected: String) {
        #expect(cleaned(input, by: terminal) == expected)
    }

    @Test("writes the reported dictation through every pass")
    func writesReportedDictation() {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        #expect(pipeline.run(Draft(text: "ssh john at example dot com")).text == "ssh john@example.com")
    }

    @Test("keeps the words where nothing announces an address")
    func leavesUnannouncedWords() {
        #expect(cleaned("meet john at example dot com", by: terminal) == "meet john at example.com")
        #expect(cleaned("john at example dot com", by: prose) == "john at example.com")
    }
}
