import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken scheme at a command line", .bug(id: 7879))
struct SpokenSchemeTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "writes any scheme, its slashes and its host as one address at a command line",
        arguments: [
            ("aws s3 ls s3 colon slash slash bucket", "aws s3 ls s3://bucket"),
            ("aws s3 cp notes dot txt s3 colon slash slash bucket", "aws s3 cp notes.txt s3://bucket"),
            (
                "psql postgres colon slash slash localhost colon five four three two",
                "psql postgres://localhost:5432"
            ),
            (
                "gsutil ls gs colon slash slash media dash bucket slash photos",
                "gsutil ls gs://media-bucket/photos"
            ),
        ]
    )
    func writesSchemes(input: String, expected: String) {
        #expect(cleaned(input, by: terminal) == expected)
    }

    @Test("writes the reported dictation through every pass")
    func writesReportedDictation() {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        let spoken = "aws s3 ls s3 colon slash slash bucket"
        #expect(pipeline.run(Draft(text: spoken)).text == "aws s3 ls s3://bucket")
    }

    @Test("keeps a web scheme as before, and any other scheme outside a command line")
    func leavesOtherSchemes() {
        #expect(cleaned("curl http colon slash slash localhost", by: terminal) == "curl http://localhost")
        let spoken = "aws s3 ls s3 colon slash slash bucket"
        #expect(cleaned(spoken, by: prose) != "aws s3 ls s3://bucket")
    }
}
