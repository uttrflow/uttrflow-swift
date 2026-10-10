// A stored digit-string run, per shape, that later runs are gated against.
public import Foundation

/// The per-shape exact counts of one digit-string run, on the recogniser's text and after the rules.
public struct DigitStringBaseline: Sendable, Equatable, Codable {
    /// One shape's exact counts, kept as counts so the rates and their intervals can be recomputed.
    public struct Shape: Sendable, Equatable, Codable {
        public let shape: DigitShape
        public let rawExact: Int
        public let finalExact: Int
        public let cases: Int
    }

    /// What was measured: model, compute plan and voices; runs with different labels are never compared.
    public let label: String
    public let recordedAt: Date
    public let shapes: [Shape]

    public init(label: String, recordedAt: Date, report: DigitStringReport) {
        self.label = label
        self.recordedAt = recordedAt
        shapes = report.rows.map {
            Shape(shape: $0.shape, rawExact: $0.raw.hits, finalExact: $0.final.hits, cases: $0.raw.total)
        }
    }

    /// The shapes where `measured` has fewer exact cases than this baseline, raw or final, or why the two cannot be compared.
    public func worsened(in measured: DigitStringBaseline) -> Result<[DigitShape], Incomparable> {
        guard measured.label == label else {
            return .failure(Incomparable(reason: "measured \"\(measured.label)\", baseline \"\(label)\""))
        }
        let before = Dictionary(uniqueKeysWithValues: shapes.map { ($0.shape, $0) })
        guard measured.shapes.map(\.shape) == shapes.map(\.shape),
            measured.shapes.allSatisfy({ before[$0.shape]?.cases == $0.cases })
        else {
            return .failure(Incomparable(reason: "the cases per shape differ from the baseline's"))
        }
        return .success(
            measured.shapes.filter { now in
                guard let was = before[now.shape] else { return false }
                return now.rawExact < was.rawExact || now.finalExact < was.finalExact
            }.map(\.shape))
    }

    /// Why a run and a baseline do not describe the same thing.
    public struct Incomparable: Error, Sendable, Equatable {
        public let reason: String
    }

    // MARK: On disk

    public func write(to url: URL) throws(EvaluationStoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .readable
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            throw .couldNotWrite(path: url.lastPathComponent, reason: "\(error)")
        }
    }

    /// Reads through a file path, so the baseline is only ever a local file.
    public static func read(from url: URL) throws(EvaluationStoreError) -> DigitStringBaseline {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw .couldNotRead(path: url.lastPathComponent, reason: "no file")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DigitStringBaseline.self, from: data)
        } catch {
            throw .couldNotRead(path: url.lastPathComponent, reason: "\(error)")
        }
    }
}
