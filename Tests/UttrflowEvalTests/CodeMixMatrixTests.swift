import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowEval

/// The code-mixing matrix: filled cells meet the floor, outputs stay Latin, and the page matches the corpus.
@Suite("The code-mixing coverage matrix")
struct CodeMixMatrixTests {
    /// The generated page, three folders above this test file.
    static let page = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/code-mixing-matrix.md")

    @Test("gives every cell at least the covered floor of cases")
    func everyCellIsCovered() {
        for row in CodeMixMatrix().rows {
            #expect(row.isCovered, "\(row.cell) has \(row.caseIDs.count) cases")
        }
    }

    @Test("keeps every expected output in Latin letters")
    func expectedIsLatin() {
        for item in EvaluationCorpus.codeMixing {
            #expect(item.expected.unicodeScalars.allSatisfy { $0.isASCII }, "\(item.id)")
        }
    }

    @Test("keeps every must-keep word in the expected output")
    func expectedKeepsWords() {
        for item in EvaluationCorpus.codeMixing {
            for word in item.mustKeep { #expect(item.expected.contains(word), "\(item.id): \(word)") }
            for word in item.mustNotAdd {
                #expect(!item.expected.lowercased().contains(word.lowercased()), "\(item.id): \(word)")
            }
        }
    }

    @Test("matches Docs/code-mixing-matrix.md, which is generated from the corpus")
    func pageMatchesCorpus() throws {
        let generated = CodeMixMatrix().markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.page, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.page, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the page")
    }
}
