import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A connection URI said in any app", .bug(id: 7917))
struct SpokenConnectionURITests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    private static let cases: [(String, String)] = [
        (
            "redis colon slash slash localhost colon sixty three seventy nine slash zero",
            "redis://localhost:6379/0"
        ),
        (
            "mongodb colon slash slash localhost colon twenty seven thousand seventeen",
            "mongodb://localhost:27017"
        ),
        (
            "postgres colon slash slash app at db dot example dot com slash orders",
            "postgres://app@db.example.com/orders"
        ),
        (
            "ws colon slash slash localhost colon eight zero eight zero slash socket",
            "ws://localhost:8080/socket"
        ),
        ("ftp colon slash slash files dot example dot com slash pub", "ftp://files.example.com/pub"),
    ]

    @Test("writes the scheme, host, port and path outside a command line", arguments: cases)
    func writesInProse(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
    }

    @Test("writes the same address at a command line", arguments: cases)
    func writesAtCommandLine(input: String, expected: String) {
        #expect(cleaned(input, by: terminal) == expected)
    }
}
