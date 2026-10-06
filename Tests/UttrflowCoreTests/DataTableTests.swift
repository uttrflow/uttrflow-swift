// Tests for reading a bundled data table: the shipped tables, malformed input, and the compiled fallback.

import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowCore

@Suite("A bundled table is used only when it is well formed, and otherwise falls back and says why")
struct DataTableTests {
    private struct Row: DataTableRow, Equatable {
        let id: String
        let weight: Int
    }

    private let limits = DataTableLimits(maxBytes: 4_096, maxRows: 4)

    private func decode(_ json: String, schema: Int = 1) throws(DataTableError) -> [Row] {
        try DataTable<Row>.decode(Data(json.utf8), schema: schema, limits: limits)
    }

    private func failure(_ json: String, schema: Int = 1) -> DataTableError? {
        do {
            _ = try decode(json, schema: schema)
            return nil
        } catch {
            return error
        }
    }

    /// A temporary bundle folder holding `files`, keyed by file name.
    private func bundle(_ files: [String: String], folders: [String] = []) throws -> Bundle {
        let url = URL.temporaryDirectory.appending(
            path: "uttrflow-table-\(UUID().uuidString).bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, text) in files { try Data(text.utf8).write(to: url.appending(path: name)) }
        for name in folders {
            try FileManager.default.createDirectory(
                at: url.appending(path: name), withIntermediateDirectories: true)
        }
        return try #require(Bundle(url: url))
    }

    @Test("A well-formed table decodes to its rows in file order.")
    func wellFormed() throws {
        let rows = try decode(#"{"schema": 1, "rows": [{"id": "b", "weight": 2}, {"id": "a", "weight": 1}]}"#)
        #expect(rows == [Row(id: "b", weight: 2), Row(id: "a", weight: 1)])
    }

    @Test("Each kind of malformed input is refused with its own reason.")
    func malformedInputs() {
        #expect(failure("") == .malformed)
        #expect(failure("[]") == .malformed)
        #expect(failure(#"{"rows": []}"#) == .malformed)
        #expect(failure(#"{"schema": "1", "rows": []}"#) == .malformed)
        #expect(failure(#"{"schema": 1}"#) == .malformed)
        #expect(failure(#"{"schema": 1, "rows": [{"id": "a"}]}"#) == .malformed)
        #expect(failure(#"{"schema": 1, "rows": [{"id": "a", "weight": "x"}]}"#) == .malformed)
        #expect(failure(#"{"schema": 2, "rows": []}"#) == .unsupportedSchema(found: 2))
        #expect(failure(#"{"schema": 1, "rows": [{"id": " ", "weight": 1}]}"#) == .blankID(row: 0))
        #expect(
            failure(#"{"schema": 1, "rows": [{"id": "a", "weight": 1}, {"id": "a", "weight": 2}]}"#)
                == .duplicateID("a"))
    }

    @Test("A table over its row limit is refused with the count it held.")
    func tooManyRows() {
        let rows = (0..<5).map { #"{"id": "r\#($0)", "weight": 0}"# }.joined(separator: ",")
        #expect(failure(#"{"schema": 1, "rows": [\#(rows)]}"#) == .tooManyRows(count: 5))
    }

    @Test("A file over the byte limit is refused before it is parsed.")
    func tooLarge() {
        let padding = String(repeating: " ", count: 4_097)
        #expect(failure(padding) == .tooLarge(bytes: 4_097))
    }

    @Test("Random damage to a valid table never crashes and never yields a row that breaks the rules.")
    func fuzzedInput() {
        let valid = Array(
            #"{"schema": 1, "rows": [{"id": "a", "weight": 1}, {"id": "b", "weight": 2}]}"#.utf8)
        let alphabet = Array(#"{}[]":, 0129abschemrowsidwt-.\"#.utf8)
        var random = Seeded(seed: 0x5EED_7AB1E)
        var decoded = 0
        for _ in 0..<5_000 {
            var bytes = valid
            for _ in 0..<Int.random(in: 1...4, using: &random) {
                let position = Int.random(in: 0..<bytes.count, using: &random)
                switch Int.random(in: 0..<3, using: &random) {
                case 0: bytes[position] = alphabet.randomElement(using: &random) ?? 0
                case 1: bytes.remove(at: position)
                default: bytes.insert(alphabet.randomElement(using: &random) ?? 0, at: position)
                }
            }
            guard let rows = try? DataTable<Row>.decode(Data(bytes), schema: 1, limits: limits) else {
                continue
            }
            decoded += 1
            #expect(Set(rows.map(\.id)).count == rows.count)
            #expect(rows.allSatisfy { !$0.id.allSatisfy(\.isWhitespace) })
        }
        #expect(decoded > 0)
    }

    @Test(
        "Every truncation and every single-bit flip of a valid table is refused or decodes within the rules.")
    func exhaustiveDamage() {
        let valid = Array(
            #"{"schema": 1, "rows": [{"id": "a", "weight": 1}, {"id": "b", "weight": 2}]}"#.utf8)
        var damaged = (0..<valid.count).map { Array(valid.prefix($0)) }
        for position in valid.indices {
            for bit in 0..<8 {
                var bytes = valid
                bytes[position] ^= UInt8(1) << bit
                damaged.append(bytes)
            }
        }
        for bytes in damaged {
            guard let rows = try? DataTable<Row>.decode(Data(bytes), schema: 1, limits: limits) else {
                continue
            }
            #expect(rows.count <= limits.maxRows)
            #expect(Set(rows.map(\.id)).count == rows.count)
            #expect(rows.allSatisfy { !$0.id.allSatisfy(\.isWhitespace) })
        }
        #expect(damaged.count == valid.count * 9)
    }

    @Test("A bundled file that is well formed is used, and says so.")
    func loadsFromBundle() throws {
        let source = try bundle(["weights.json": #"{"schema": 1, "rows": [{"id": "a", "weight": 1}]}"#])
        let table = DataTable<Row>.load("weights", schema: 1, from: source, fallback: [], limits: limits)
        #expect(table.rows == [Row(id: "a", weight: 1)])
        #expect(table.source == .bundled)
    }

    @Test("A missing file keeps the compiled default and records that it was missing.")
    func missingFallsBack() throws {
        let fallback = [Row(id: "default", weight: 0)]
        let table = DataTable<Row>.load("weights", schema: 1, from: try bundle([:]), fallback: fallback)
        #expect(table.rows == fallback)
        #expect(table.source == .fallback(.missing(name: "weights")))
    }

    @Test("A file that cannot be read keeps the compiled default and records why.")
    func unreadableFallsBack() throws {
        let table = DataTable<Row>.load(
            "weights", schema: 1, from: try bundle([:], folders: ["weights.json"]), fallback: [])
        #expect(table.rows.isEmpty)
        #expect(table.source == .fallback(.unreadable(name: "weights")))
    }

    @Test("A malformed file keeps the compiled default and records the schema it found.")
    func malformedFallsBack() throws {
        let source = try bundle(["weights.json": #"{"schema": 9, "rows": []}"#])
        let fallback = [Row(id: "default", weight: 0)]
        let table = DataTable<Row>.load("weights", schema: 1, from: source, fallback: fallback)
        #expect(table.rows == fallback)
        #expect(table.source == .fallback(.unsupportedSchema(found: 9)))
    }

    @Test(
        "The shipped word tables load from the bundle with every word they held when they were written in code."
    )
    func shippedTables() {
        #expect(FunctionWords.table.source == .bundled)
        #expect(Restatement.table.source == .bundled)
        #expect(CredentialWords.table.source == .bundled)
        #expect(FunctionWords.table.rows.count == 203)
        #expect(FunctionWords.all.count == 199)
        #expect(FunctionWords.leadingOn.count == 38)
        #expect(FunctionWords.meaningBearing.count == 75)
        #expect(FunctionWords.leadingOn.contains("let\u{2019}s"))
        #expect(NumberWords.table.source == .bundled)
        #expect(NumberCues.table.source == .bundled)
        #expect(NumberCues.words(for: .dotted).count == 6)
        #expect(NumberCues.words(for: .digitRun).count == 12)
        #expect(NumberCues.words(for: .coordinator).count == 6)
        #expect(NumberCues.words(for: .range) == ["to", "through"])
        #expect(NumberWords.units.count == 10)
        #expect(NumberWords.teens.count == 10)
        #expect(NumberWords.tens.count == 8)
        #expect(
            NumberWords.scales == [
                "hundred": 100, "thousand": 1_000, "million": 1_000_000,
                "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
            ])
    }
}
