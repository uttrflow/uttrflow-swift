import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A port said as two spoken pairs", .bug(id: 7918))
struct SpokenPortPairTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "writes the two pairs side by side as one port",
        arguments: [
            ("localhost colon sixty three seventy nine", "localhost:6379"),
            ("connect to localhost colon eighty eighty", "connect to localhost:8080"),
            ("connect to localhost colon fifty four thirty two", "connect to localhost:5432"),
            ("open example dot com colon eighty eighty slash admin", "open example.com:8080/admin"),
        ]
    )
    func writesPairedPort(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
    }

    @Test("writes the reported scheme, host, port and path at a command line")
    func writesReportedAddress() {
        let spoken = "redis colon slash slash localhost colon sixty three seventy nine slash zero"
        #expect(cleaned(spoken, by: terminal) == "redis://localhost:6379/0")
    }

    @Test(
        "keeps a single spoken number as the port or line",
        arguments: [
            ("connect to localhost colon eighty", "connect to localhost:80"),
            ("connect to localhost colon three thousand", "connect to localhost:3000"),
            ("see main dot py colon forty two", "see main.py:42"),
        ]
    )
    func keepsSingleNumbers(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
    }
}
