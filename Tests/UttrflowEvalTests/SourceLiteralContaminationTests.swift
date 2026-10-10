// Tests that no string literal in the cleaning code copies a corpus passage.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("Source literal contamination")
struct SourceLiteralContaminationTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The directories whose rules decide what a dictation becomes.
    private static let cleaningDirectories = [
        "Sources/UttrflowAI/Passes", "Sources/UttrflowCore/Cleaning", "Sources/UttrflowPipeline",
    ]

    /// A single-line string literal, escapes included; multi-line literals are prose, not rule words.
    private static var literal: Regex<(Substring, Substring)> { /"((?:[^"\\\n]|\\.)*)"/ }

    /// Every single-line string literal in `source`.
    static func literals(in source: String) -> [String] {
        source.matches(of: literal).map { String($0.output.1) }
    }

    /// Every Swift file under the cleaning directories with its literals, by repository path.
    private static func sourceLiterals() throws -> [(path: String, literals: [String])] {
        let files = FileManager.default
        return try cleaningDirectories.flatMap { directory in
            let base = root.appending(path: directory)
            let paths =
                files.enumerator(atPath: base.path(percentEncoded: false))?.allObjects as? [String] ?? []
            return try paths.filter { $0.hasSuffix(".swift") }.sorted().map { relative in
                let text = try String(contentsOf: base.appending(path: relative), encoding: .utf8)
                return (directory + "/" + relative, literals(in: text))
            }
        }
    }

    /// Corpus copies in the cleaning code as `caseID in path: words`; the list only falls.
    static let knownCopies: Set<String> = [
        "document-number-one-after-a-sentence-not-an-item in Sources/UttrflowAI/Passes/LayoutWordsPass.swift: number one is broken",
        "false-start in Sources/UttrflowAI/Passes/RepeatedPhrasePass.swift: so i was i was thinking",
        "fmt-casing-mention-the-rule in Sources/UttrflowAI/Passes/MentionGuard.swift: the all caps rule",
        "fmt-question-tag in Sources/UttrflowCore/Cleaning/QuestionShape.swift: the meeting is at three",
        "full-stop-new-paragraph in Sources/UttrflowAI/Passes/LayoutWordsPass.swift: full stop new paragraph",
        "message-two-sentences-no-stop in Sources/UttrflowCore/Cleaning/QuestionShape.swift: are you around yet i should be there",
        "name-opening-is-the-owner-statement in Sources/UttrflowCore/Cleaning/QuestionShape.swift: ravi is the owner",
        "number-correction-with-unit in Sources/UttrflowCore/Cleaning/Restatement.swift: twelve boxes i mean fifteen boxes",
        "probe-clinical-note in Sources/UttrflowAI/Passes/SpelledInitialismPass.swift: eighty one m g",
        "sql-editor-large-number-ungrouped in Sources/UttrflowAI/Passes/TerminalStopPass.swift: where total is greater than 12000",
    ]

    @Test("no new literal in the cleaning code carries a corpus passage, and the known copies only fall")
    func cleaningLiteralsAreClean() throws {
        let audit = ContaminationAudit.corpus
        let sources = try Self.sourceLiterals()
        #expect(sources.count >= 50, "the cleaning directories hold no Swift to audit")
        let found = Set(
            sources.flatMap { audit.findings(in: $0.literals, asset: $0.path) }.map(\.description))
        #expect(found.subtracting(Self.knownCopies).sorted() == [], "new corpus copies in the cleaning code")
        #expect(Self.knownCopies.subtracting(found).sorted() == [], "remove these lines from knownCopies")
    }

    @Test("a corpus phrase planted in a literal is caught with its case id")
    func plantedPhraseIsCaught() throws {
        let planted = try #require(EvaluationCorpus.all.first { Scorer.tokens($0.spoken).count >= 4 })
        let phrase = Scorer.tokens(planted.spoken).prefix(4).joined(separator: " ")
        let source = "let words = [\"\(phrase)\", \"git\"]\nlet escaped = \"a \\\"quoted\\\" word\""
        #expect(Self.literals(in: source) == [phrase, "git", "a \\\"quoted\\\" word"])
        let findings = ContaminationAudit.corpus.findings(
            in: Self.literals(in: source), asset: "Planted.swift")
        #expect(findings.contains { $0.caseID == planted.id && $0.asset == "Planted.swift" })
    }
}
