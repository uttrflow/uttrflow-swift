// Per-adapter counts over a scored corpus, and the stored run later runs are gated against.
public import Foundation
import UttrflowCore

/// What one adapter's cases scored: exact written form, added words and broken shape, kept as counts.
public struct AdapterReport: Sendable, Equatable, Codable {
    /// One adapter's counts, kept as counts so the rates can be recomputed exactly.
    public struct Row: Sendable, Equatable, Codable {
        public let adapter: String
        /// Every case the adapter owns that the engine attempted.
        public let cases: Int
        /// Attempted cases that name an exact written form.
        public let exactCases: Int
        /// Exact cases whose output was that form, character for character.
        public let exactHits: Int
        /// Words the outputs invented that the cases forbid, summed; the gate holds this at 0.
        public let addedTokens: Int
        /// Required beginnings, endings and exact forms the outputs broke, summed; the gate holds this at 0.
        public let shapeViolations: Int

        /// Exact-match rate over the exact cases, or `nil` when the adapter has none.
        public var exactMatchRate: Double? {
            exactCases > 0 ? Double(exactHits) / Double(exactCases) : nil
        }
    }

    /// What was measured: engine and corpus; runs with different labels are never compared.
    public let label: String
    public let recordedAt: Date
    /// One row per adapter, in adapter-name order.
    public let rows: [Row]

    public init(label: String, recordedAt: Date = Date(), rows: [Row]) {
        self.label = label
        self.recordedAt = recordedAt
        self.rows = rows.sorted { $0.adapter < $1.adapter }
    }

    /// Groups the scores of the cases that name an adapter; a case with no adapter, or no score, is left out.
    public init(label: String, recordedAt: Date = Date(), cases: [EvaluationCase], scores: [CaseScore]) {
        let byID = Dictionary(scores.map { ($0.caseID, $0) }, uniquingKeysWith: { first, _ in first })
        var grouped: [String: [(EvaluationCase, CaseScore)]] = [:]
        for evaluated in cases {
            guard let adapter = evaluated.adapter, let score = byID[evaluated.id], !score.declined else {
                continue
            }
            grouped[adapter.rawValue, default: []].append((evaluated, score))
        }
        let rows = grouped.map { adapter, pairs in
            let exact = pairs.filter { $0.0.expectedExact != nil }
            return Row(
                adapter: adapter,
                cases: pairs.count,
                exactCases: exact.count,
                exactHits: exact.count(where: { !$0.1.brokeShape.contains { $0.hasPrefix("is exactly") } }),
                addedTokens: pairs.reduce(0) { $0 + $1.1.invented.count },
                shapeViolations: pairs.reduce(0) { $0 + $1.1.brokeShape.count })
        }
        self.init(label: label, recordedAt: recordedAt, rows: rows)
    }

    /// Why a run and a baseline do not describe the same thing.
    public struct Incomparable: Error, Sendable, Equatable {
        public let reason: String
    }

    /// The adapters where this run has fewer exact hits, or any added word or broken shape, than the baseline allows.
    ///
    /// Added words and broken shapes must be 0, so they fail against 0 whatever the baseline held.
    public func worsened(against baseline: AdapterReport) -> Result<[String], Incomparable> {
        guard label == baseline.label else {
            return .failure(Incomparable(reason: "measured \"\(label)\", baseline \"\(baseline.label)\""))
        }
        let before = Dictionary(uniqueKeysWithValues: baseline.rows.map { ($0.adapter, $0) })
        guard rows.map(\.adapter) == baseline.rows.map(\.adapter),
            rows.allSatisfy({ before[$0.adapter]?.cases == $0.cases })
        else {
            return .failure(
                Incomparable(reason: "the adapters or their case counts differ from the baseline's"))
        }
        return .success(
            rows.filter { now in
                guard let was = before[now.adapter] else { return false }
                return now.exactHits < was.exactHits || now.addedTokens > 0 || now.shapeViolations > 0
            }.map(\.adapter))
    }

    /// The table `make bakeoff` prints, one line per adapter.
    public var table: String {
        guard !rows.isEmpty else { return "no case names an adapter" }
        return rows.map { row in
            let rate = row.exactMatchRate.map { String(format: "%.1f%%", $0 * 100) } ?? "n/a"
            return "\(row.adapter): \(row.cases) cases, exact \(row.exactHits)/\(row.exactCases) (\(rate)), "
                + "added \(row.addedTokens), shape violations \(row.shapeViolations)"
        }.joined(separator: "\n")
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
    public static func read(from url: URL) throws(EvaluationStoreError) -> AdapterReport {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw .couldNotRead(path: url.lastPathComponent, reason: "no file")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AdapterReport.self, from: data)
        } catch {
            throw .couldNotRead(path: url.lastPathComponent, reason: "\(error)")
        }
    }
}
