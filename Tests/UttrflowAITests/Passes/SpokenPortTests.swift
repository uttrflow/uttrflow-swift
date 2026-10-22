import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A port said after a spoken colon", .bug(id: 7918))
struct SpokenPortTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "writes a port said as two two-digit halves as its four digits",
        arguments: [
            ("connect to localhost colon eighty eighty", "connect to localhost:8080"),
            ("connect to localhost colon fifty four thirty two", "connect to localhost:5432"),
            ("ssh to ten dot zero dot zero dot one colon twenty two twenty two", "ssh to 10.0.0.1:2222"),
            ("open example dot com colon eighty eighty slash admin", "open example.com:8080/admin"),
        ]
    )
    func writesHalves(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
    }

    @Test("writes the halves inside a URL at a command line")
    func writesHalvesInURL() {
        let spoken = "redis colon slash slash localhost colon sixty three seventy nine slash zero"
        #expect(cleaned(spoken, by: terminal) == "redis://localhost:6379/0")
    }

    @Test(
        "keeps a port said as one number, and a line number followed by a smaller one",
        arguments: [
            ("connect to localhost colon eight thousand", "connect to localhost:8000"),
            ("see main dot py colon forty two seven", "see main.py:42 seven"),
            ("connect to localhost colon twenty seven thousand seventeen", "connect to localhost:27017"),
        ]
    )
    func keepsSingleNumbers(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
    }
}
