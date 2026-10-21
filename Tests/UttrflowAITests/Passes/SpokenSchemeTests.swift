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

    @Test(
        "writes any scheme before a host the words show is one, in every destination",
        .bug(id: 7917),
        arguments: [
            (
                "mongodb colon slash slash localhost colon twenty seven thousand seventeen",
                "mongodb://localhost:27017"
            ),
            (
                "ws colon slash slash localhost colon eight zero eight zero slash socket",
                "ws://localhost:8080/socket"
            ),
            ("ftp colon slash slash files dot example dot com slash pub", "ftp://files.example.com/pub"),
            ("ssh colon slash slash ten dot zero dot zero dot one", "ssh://10.0.0.1"),
        ]
    )
    func writesSchemesBeforeKnownHosts(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
        #expect(cleaned(input, by: terminal) == expected)
    }

    @Test(
        "writes the user said before the host's at",
        .bug(id: 7917),
        arguments: [
            (
                "postgres colon slash slash app at db dot example dot com slash orders",
                "postgres://app@db.example.com/orders"
            ),
            (
                "psql postgres colon slash slash app at localhost colon five four three two",
                "psql postgres://app@localhost:5432"
            ),
            ("https colon slash slash sam at example dot com", "https://sam@example.com"),
        ]
    )
    func writesUserInfo(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
        #expect(cleaned(input, by: terminal) == expected)
    }
}
