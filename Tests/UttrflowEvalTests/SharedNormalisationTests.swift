// Pins the shared normalisation table that the Python bench is tested against too.
private import Foundation
import Testing

@testable import UttrflowEval

/// The one table both entry points read, so the Swift scorers and the bench cannot drift apart again.
@Suite("Shared normalisation table")
struct SharedNormalisationTests {
    private static let table = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Golden/normalisation.tsv")

    @Test("the standard normaliser gives every recorded line exactly its recorded words")
    func matchesTable() throws {
        let rows = try String(contentsOf: Self.table, encoding: .utf8).split(separator: "\n")
        #expect(!rows.isEmpty)
        for row in rows {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            try #require(fields.count == 2, "line needs text and words: \(row)")
            #expect(TextNormaliser.standard.normalised(fields[0]) == fields[1], "\(fields[0])")
        }
    }
}
