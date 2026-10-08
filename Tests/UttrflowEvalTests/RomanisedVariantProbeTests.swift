import Foundation
import Testing
import UttrflowCore

/// How well `Romaniser.soundKey` judges two romanised spellings to be one word, against attested variant sets and pairs that must stay apart. See `Docs/latin-output.md`.
@Suite("Romanised spelling variants against the sound key")
struct RomanisedVariantProbeTests {
    /// One Hindi word as it is most often typed, with the other spellings people type for it.
    struct VariantSet: DataTableRow {
        let id: String
        let variants: [String]
    }

    /// Two romanised words that are different words and must not share a key.
    struct DistinctPair: DataTableRow {
        let id: String
        let left: String
        let right: String
    }

    static func table<Row: DataTableRow>(_ name: String, in folder: URL) throws -> [Row] {
        let url = folder.appending(path: "\(name).json")
        return try DataTable<Row>.decode(try Data(contentsOf: url), schema: 1, limits: .standard)
    }

    static let testFolder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Golden")
    static let tableFolder = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/UttrflowCore/Resources/Tables").standardized

    @Test("the tables hold at least 150 variant sets and 50 distinct pairs, in Latin letters only")
    func tablesAreLargeEnough() throws {
        let sets: [VariantSet] = try Self.table("romanised-variants", in: Self.tableFolder)
        let pairs: [DistinctPair] = try Self.table("romanised-distinct-words", in: Self.testFolder)
        #expect(sets.count >= 150)
        #expect(pairs.count >= 50)
        let words = sets.flatMap { [$0.id] + $0.variants } + pairs.flatMap { [$0.left, $0.right] }
        #expect(words.allSatisfy { $0.unicodeScalars.allSatisfy { $0.isASCII } })
    }

    @Test("sound key recall and false merges match the figures in Docs/latin-output.md")
    func soundKeyMeasured() throws {
        let sets: [VariantSet] = try Self.table("romanised-variants", in: Self.tableFolder)
        let pairs: [DistinctPair] = try Self.table("romanised-distinct-words", in: Self.testFolder)
        let variantPairs = sets.flatMap { set in set.variants.map { (set.id, $0) } }
        let merged = variantPairs.filter { Romaniser.soundKey($0.0) == Romaniser.soundKey($0.1) }
        let falseMerges = pairs.filter { Romaniser.soundKey($0.left) == Romaniser.soundKey($0.right) }
        #expect(variantPairs.count == 309)
        #expect(merged.count == variantPairs.count)
        #expect(pairs.count == 55)
        #expect(falseMerges.isEmpty)
    }
}
