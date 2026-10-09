import Foundation
import Testing

@testable import UttrflowEval

/// A committed fit table reproduces its weights and refuses anything that could carry speech.
@Suite("Fit table")
struct FitTableTests {
    static let url = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "FitTables/invented-linear.json")
    static let committedDigest = "cea62c4bbfd6e1b5010fd91d2224fc87d3528b2197b884f8c65c72257182e80b"

    static func row(_ extra: String) -> Data {
        Data(
            """
            {"schemaVersion":1,"featureSpecVersion":1,"rows":[{"ordinal":0,"split":"development",\
            "language":"english","label":"right","features":[0.5]\(extra)}]}
            """.utf8)
    }

    @Test("The committed table reproduces the committed weights digest with no audio")
    func reproduces() throws {
        let data = try Data(contentsOf: Self.url)
        #expect(data.count < FitTable.byteLimit)
        let table = try FitTable.read(data)
        #expect(table.rows.count == 240)
        #expect(table.fitLinearScorer().digest == Self.committedDigest)
    }

    @Test("A table survives its own canonical encoding unchanged")
    func canonical() throws {
        let data = try Data(contentsOf: Self.url)
        let table = try FitTable.read(data)
        #expect(try FitTable.read(table.encoded()) == table)
    }

    @Test("Held-out rows never reach the fit")
    func heldOutKeptBack() throws {
        let table = try FitTable.read(Data(contentsOf: Self.url))
        let development = table.rows.filter { $0.split == .development }.count
        #expect(table.developmentRows.count == development)
        #expect(development < table.rows.count)
    }

    @Test("A row carrying a free-text field is refused")
    func freeTextFieldRefused() {
        #expect(throws: FitTable.SchemaError.unexpectedField(path: "rows[0].text")) {
            try FitTable.read(Self.row(#","text":"please send the file""#))
        }
    }

    @Test("A closed field holding text outside its set is refused")
    func openEnumRefused() {
        let data = Data(
            """
            {"schemaVersion":1,"featureSpecVersion":1,"rows":[{"ordinal":0,"split":"development",\
            "language":"send the file","label":"right","features":[0.5]}]}
            """.utf8)
        #expect(throws: FitTable.SchemaError.freeText(path: "rows[0].language")) { try FitTable.read(data) }
    }

    @Test("A field outside the schema at the top level is refused")
    func topLevelFieldRefused() {
        let data = Data(#"{"schemaVersion":1,"featureSpecVersion":1,"rows":[],"source":"a"}"#.utf8)
        #expect(throws: FitTable.SchemaError.unexpectedField(path: "source")) { try FitTable.read(data) }
    }

    @Test("Rows of different widths are refused")
    func raggedRefused() {
        let data = Data(
            """
            {"schemaVersion":1,"featureSpecVersion":1,"rows":[\
            {"ordinal":0,"split":"development","language":"english","label":"right","features":[0.5]},\
            {"ordinal":1,"split":"development","language":"hindi","label":"wrong","features":[0.5,1]}]}
            """.utf8)
        #expect(throws: FitTable.SchemaError.ragged(ordinal: 1)) { try FitTable.read(data) }
    }

    @Test("A table over the size limit is refused before it is parsed")
    func oversizeRefused() {
        let data = Data(count: FitTable.byteLimit + 1)
        #expect(throws: FitTable.SchemaError.tooLarge(bytes: FitTable.byteLimit + 1)) {
            try FitTable.read(data)
        }
    }

    @Test("A wrong schema version is refused")
    func versionRefused() {
        let data = Data(#"{"schemaVersion":2,"featureSpecVersion":1,"rows":[]}"#.utf8)
        #expect(throws: FitTable.SchemaError.wrongSchemaVersion(2)) { try FitTable.read(data) }
    }

    @Test("Malformed input is refused with a reason that names where")
    func malformedRefused() {
        let cases: [(String, FitTable.SchemaError)] = [
            ("[]", .notAnObject(path: "table")),
            (#"{"schemaVersion":1,"featureSpecVersion":1}"#, .notAnObject(path: "rows")),
            (#"{"schemaVersion":1,"featureSpecVersion":1,"rows":[1]}"#, .notAnObject(path: "rows[0]")),
        ]
        for (text, error) in cases {
            #expect(throws: error) { try FitTable.read(Data(text.utf8)) }
            #expect(!error.description.isEmpty)
        }
        #expect(throws: FitTable.SchemaError.self) { try FitTable.read(Data("not json".utf8)) }
        #expect(throws: FitTable.SchemaError.self) {
            try FitTable.read(
                Data(#"{"schemaVersion":1,"featureSpecVersion":1,"rows":[{"ordinal":0.5}]}"#.utf8))
        }
        let others: [FitTable.SchemaError] = [
            .tooLarge(bytes: 1), .unexpectedField(path: "a"), .freeText(path: "a"), .wrongSchemaVersion(2),
            .ragged(ordinal: 1), .undecodable("a"),
        ]
        #expect(others.allSatisfy { !$0.description.isEmpty })
    }
}
