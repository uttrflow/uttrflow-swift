import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The ordered readers scored on each known ambiguity in `Docs/cleanup.md`, the measurement that keeps them.
@Suite("The number grammar's reader order")
struct NumberGrammarStructureTests {
    static let ambiguities: [(spoken: String, expected: String, semiotic: SemioticClass)] = [
        ("the call is at two thirty", "The call is at 2:30.", .time),
        ("meet at seven thirty", "Meet at 7:30.", .time),
        ("the meeting is at seven thirty pm", "The meeting is at 7:30 pm.", .time),
        ("he was born in nineteen thirty", "He was born in 1930.", .date),
        ("set an alarm for seven oh five", "Set an alarm for 7:05.", .time),
        ("the code is one two three four", "The code is 1234.", .telephone),
        ("music from the nineteen nineties", "Music from the 1990s.", .date),
        ("ten minus three is seven", "10 minus three is seven.", .cardinal),
        ("it costs two ninety nine", "It costs 299.", .money),
        ("two thirds of the team", "Two thirds of the team.", .fraction),
        ("give me a second", "Give me a second.", .staysWords),
        ("no one came", "No one came.", .staysWords),
        ("about a hundred users", "About a hundred users.", .staysWords),
        ("we use python three", "We use Python three.", .staysWords),
        ("may fifth works", "May fifth works.", .staysWords),
        ("in twenty oh five", "In 2005.", .date),
        (
            "the server is one nine two dot one six eight dot one dot one", "The server is 192.168.1.1.",
            .electronic
        ),
        ("double oh seven", "007", .telephone),
        ("fifty k", "50 k.", .cardinal),
    ]

    @Test("writes every known ambiguity as expected, with no value error and no false conversion")
    func everyAmbiguityExact() async throws {
        for row in Self.ambiguities {
            let testCase = EvaluationCase(
                id: "ambiguity", category: .everyday, spoken: row.spoken, expected: row.expected,
                mustKeep: [],
                classes: [.numbers], semiotic: row.semiotic)
            let output = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
            let score = NumberGrammarScore(expected: row.expected, output: output)
            #expect(score.isExact, "\(row.spoken) -> \(output)")
            #expect(!score.isValueError, "\(row.spoken) -> \(output)")
            #expect(score.falseConversions == 0, "\(row.spoken) -> \(output)")
        }
    }
}
