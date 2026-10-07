// The text-free table a fit reads, committed so a fitted artifact can be rebuilt without the recordings.
public import Foundation

/// Whether the candidate a row describes was the right one; a closed class, never a word.
public enum FitLabelClass: String, Sendable, Equatable, CaseIterable, Codable {
    case right
    case wrong
}

/// One row of a fit table: closed enums, numbers and a salted ordinal, and nothing that carries a voice or a sentence.
public struct FitTableRow: Sendable, Equatable, Codable {
    /// A position in the table, salted at reduction time, so it names no recording or passage.
    public let ordinal: Int
    public let split: CorpusSplit
    public let language: TranscriptionCase.Language
    public let label: FitLabelClass
    public let features: [Double]

    public init(
        ordinal: Int, split: CorpusSplit, language: TranscriptionCase.Language, label: FitLabelClass,
        features: [Double]
    ) {
        self.ordinal = ordinal
        self.split = split
        self.language = language
        self.label = label
        self.features = features
    }
}

/// A committed fit table and the feature spec version its vectors were built under.
public struct FitTable: Sendable, Equatable, Codable {
    public static let schemaVersion = 1
    /// The largest table that may be committed, in bytes.
    public static let byteLimit = 5_000_000

    public let schemaVersion: Int
    let featureSpecVersion: Int
    public let rows: [FitTableRow]

    public init(featureSpecVersion: Int, rows: [FitTableRow]) {
        self.schemaVersion = Self.schemaVersion
        self.featureSpecVersion = featureSpecVersion
        self.rows = rows
    }

    /// Why a table cannot be committed or read.
    enum SchemaError: Error, Equatable, CustomStringConvertible {
        case tooLarge(bytes: Int)
        case notAnObject(path: String)
        case unexpectedField(path: String)
        case freeText(path: String)
        case wrongSchemaVersion(Int)
        case ragged(ordinal: Int)
        case undecodable(String)

        var description: String {
            switch self {
            case .tooLarge(let bytes): "table is \(bytes) bytes, over \(FitTable.byteLimit)"
            case .notAnObject(let path): "\(path) is not an object"
            case .unexpectedField(let path): "\(path) is not a field of the schema"
            case .freeText(let path): "\(path) holds text outside its closed set"
            case .wrongSchemaVersion(let version):
                "schema version \(version), expected \(FitTable.schemaVersion)"
            case .ragged(let ordinal): "row \(ordinal) has a different feature count from the first row"
            case .undecodable(let reason): "undecodable: \(reason)"
            }
        }
    }

    static let tableFields: Set<String> = ["schemaVersion", "featureSpecVersion", "rows"]
    /// The only string-valued fields, each with the closed set it must come from.
    static let closedFields: [String: Set<String>] = [
        "split": Set(CorpusSplit.allCases.map(\.rawValue)),
        "language": Set(TranscriptionCase.Language.allCases.map(\.rawValue)),
        "label": Set(FitLabelClass.allCases.map(\.rawValue)),
    ]
    static let rowFields: Set<String> = Set(closedFields.keys).union(["ordinal", "features"])

    /// Reads a table, refusing any field outside the schema and any string outside a closed set.
    public static func read(_ data: Data) throws -> FitTable {
        guard data.count <= byteLimit else { throw SchemaError.tooLarge(bytes: data.count) }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch {
            throw SchemaError.undecodable(String(describing: error))
        }
        guard let table = object as? [String: Any] else { throw SchemaError.notAnObject(path: "table") }
        if let extra = Set(table.keys).subtracting(tableFields).sorted().first {
            throw SchemaError.unexpectedField(path: extra)
        }
        guard let rows = table["rows"] as? [Any] else { throw SchemaError.notAnObject(path: "rows") }
        for (index, element) in rows.enumerated() {
            guard let row = element as? [String: Any] else {
                throw SchemaError.notAnObject(path: "rows[\(index)]")
            }
            if let extra = Set(row.keys).subtracting(rowFields).sorted().first {
                throw SchemaError.unexpectedField(path: "rows[\(index)].\(extra)")
            }
            for (key, value) in row where value is String {
                guard let allowed = closedFields[key], let text = value as? String, allowed.contains(text)
                else {
                    throw SchemaError.freeText(path: "rows[\(index)].\(key)")
                }
            }
        }
        let decoded: FitTable
        do { decoded = try JSONDecoder().decode(FitTable.self, from: data) } catch {
            throw SchemaError.undecodable(String(describing: error))
        }
        guard decoded.schemaVersion == schemaVersion else {
            throw SchemaError.wrongSchemaVersion(decoded.schemaVersion)
        }
        let width = decoded.rows.first?.features.count ?? 0
        if let ragged = decoded.rows.first(where: { $0.features.count != width }) {
            throw SchemaError.ragged(ordinal: ragged.ordinal)
        }
        return decoded
    }

    /// The table in its committed form: sorted keys, so the same rows always give the same bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The development rows as fit input; held-out rows are kept back to judge the fit.
    var developmentRows: [FitRow] {
        rows.filter { $0.split == .development }.map {
            FitRow(features: $0.features, label: $0.label == .right)
        }
    }

    /// Fits the linear scorer this table reproduces.
    public func fitLinearScorer() -> LinearScorer {
        LinearScorer.fit(developmentRows)
    }
}
