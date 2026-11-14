import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A spoken SQL statement cut by a pause reads as it does said whole")
struct SeamSQLSweepTests {
    private let pipeline: DictationPipeline = {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], clock: ManualClock())
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }()

    private let client = AppContext(
        applicationName: "TablePlus", bundleIdentifier: DestinationRules.tablePlus, precedingText: "")

    /// Invented statements, one with a clause whose piece holds no keyword when cut after "orders".
    static let statements = [
        "select id from orders where status equals quote paid unquote and total greater than twelve",
        "select name from users where age greater than thirty and city equals quote lyon unquote",
        "insert into items values open paren one comma quote pen unquote close paren",
        "update orders set status equals quote shipped unquote where id equals seven",
    ]

    @Test("every single cut of a statement matches the whole", arguments: statements)
    func everyCut(statement: String) async {
        let words = statement.split(separator: " ").map(String.init)
        let whole = await written([statement])
        #expect(whole != statement, "the whole statement is read as SQL: \(whole ?? "")")
        for cut in 1..<words.count {
            let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
            let text = await written(pieces)
            #expect(
                text == whole,
                "cut \(pieces.joined(separator: " | ")) wrote \(String(reflecting: text)) not \(String(reflecting: whole))"
            )
        }
    }

    @Test("a sentence about a statement is written as no statement whichever way it is cut")
    func proseIsNotJoinedIntoAStatement() async {
        let sentence = "select statement is slow because the join equals a full scan"
        let words = sentence.split(separator: " ").map(String.init)
        for cut in 1..<words.count {
            let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
            let text = await written(pieces) ?? ""
            #expect(
                !text.contains("=") && !text.contains("SELECT"),
                "cut \(pieces.joined(separator: " | ")) wrote \(text)")
        }
    }

    private func written(_ pieces: [String]) async -> String? {
        await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: client).text
    }
}
