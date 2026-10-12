// One sweep runner that turns a measured grid into a chosen threshold and keeps the evidence.
public import Foundation
private import CryptoKit

/// A threshold swept over a fit table feature: grid on the fit side, choice on the calibration side, test side scored once.
public struct ThresholdSweep: Sendable, Equatable {
    /// Which side of the threshold raises the flag.
    public enum Direction: String, Sendable, Equatable, Codable {
        case atOrBelow
        case atOrAbove
    }

    /// The question one sweep asks.
    public struct Request: Sendable, Equatable {
        public let parameter: String
        public let feature: Int
        public let direction: Direction
        public let grid: [Double]
        /// The most right rows the flag may catch, as a share of the right rows, judged on the fit side.
        public let falseFlagBound: Double
        public let seed: String
        /// How much worse a neighbour may score before the optimum counts as a cliff.
        public let cliffTolerance: Double
        /// Grid steps the choice moves toward its flatter neighbour; a cliff is refused at zero.
        public let marginSteps: Int
        public let engine: String

        public init(
            parameter: String, feature: Int, direction: Direction, grid: [Double], falseFlagBound: Double,
            seed: String, cliffTolerance: Double = 0.05, marginSteps: Int = 0, engine: String = ""
        ) {
            self.parameter = parameter
            self.feature = feature
            self.direction = direction
            self.grid = grid.sorted()
            self.falseFlagBound = falseFlagBound
            self.seed = seed
            self.cliffTolerance = cliffTolerance
            self.marginSteps = marginSteps
            self.engine = engine
        }
    }

    /// Wrong rows left unflagged and right rows flagged at one grid value, as shares of each label.
    public struct Score: Sendable, Equatable, Codable {
        public let missed: Double
        let falseFlags: Double
        public let rows: Int
    }

    /// One grid value with its fit and calibration scores.
    public struct Trial: Sendable, Equatable, Codable {
        public let value: Double
        public let fit: Score
        public let calibration: Score
    }

    /// How a sweep ended.
    public enum Verdict: String, Sendable, Equatable, Codable {
        case chosen
        case cliff
        case infeasible
    }

    /// Why a sweep could not run.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case emptyGrid
        case noFeature(Int)
        case emptySide(String)

        public var description: String {
            switch self {
            case .emptyGrid: "the grid is empty"
            case .noFeature(let column): "the table has no feature column \(column)"
            case .emptySide(let side): "the \(side) side holds no rows of one label"
            }
        }
    }

    /// The record a sweep keeps, byte-identical for the same inputs.
    public struct Record: Sendable, Equatable, Codable {
        public let schemaVersion: Int
        public let parameter: String
        public let feature: Int
        public let direction: Direction
        public let grid: [Double]
        let objective: String
        public let falseFlagBound: Double
        public let seed: String
        let tableDigest: String
        let featureSpecVersion: Int
        public let engine: String
        public let trials: [Trial]
        public let verdict: Verdict
        public let chosen: Double?
        public let neighbours: [Trial]
        public let marginSteps: Int
        public let cliffTolerance: Double
        /// Scored once on the rows no choice read; absent when nothing is chosen.
        public let test: Score?
        public let id: String

        /// The same record under its content identity.
        func identified() -> Self {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(self)) ?? Data()
            let digest = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
            return Self(copying: self, id: digest)
        }

        init(copying other: Self, id: String) {
            self.init(
                schemaVersion: other.schemaVersion, parameter: other.parameter, feature: other.feature,
                direction: other.direction, grid: other.grid, objective: other.objective,
                falseFlagBound: other.falseFlagBound, seed: other.seed, tableDigest: other.tableDigest,
                featureSpecVersion: other.featureSpecVersion, engine: other.engine, trials: other.trials,
                verdict: other.verdict, chosen: other.chosen, neighbours: other.neighbours,
                marginSteps: other.marginSteps, cliffTolerance: other.cliffTolerance, test: other.test, id: id
            )
        }

        init(
            schemaVersion: Int, parameter: String, feature: Int, direction: Direction, grid: [Double],
            objective: String, falseFlagBound: Double, seed: String, tableDigest: String,
            featureSpecVersion: Int, engine: String, trials: [Trial], verdict: Verdict, chosen: Double?,
            neighbours: [Trial], marginSteps: Int, cliffTolerance: Double, test: Score?, id: String
        ) {
            self.schemaVersion = schemaVersion
            self.parameter = parameter
            self.feature = feature
            self.direction = direction
            self.grid = grid
            self.objective = objective
            self.falseFlagBound = falseFlagBound
            self.seed = seed
            self.tableDigest = tableDigest
            self.featureSpecVersion = featureSpecVersion
            self.engine = engine
            self.trials = trials
            self.verdict = verdict
            self.chosen = chosen
            self.neighbours = neighbours
            self.marginSteps = marginSteps
            self.cliffTolerance = cliffTolerance
            self.test = test
            self.id = id
        }
    }

    public let record: Record

    public static let schemaVersion = 1
    static let objective = "minimise missed wrong rows on calibration, subject to the false-flag bound on fit"

    /// Runs the sweep; development rows are the fit side and held-out rows split by `seed` into calibration and test.
    public init(table: FitTable, tableData: Data, request: Request) throws {
        guard !request.grid.isEmpty else { throw Failure.emptyGrid }
        guard request.feature >= 0, !table.rows.isEmpty,
            table.rows.allSatisfy({ request.feature < $0.features.count })
        else {
            throw Failure.noFeature(request.feature)
        }
        let fit = table.rows.filter { $0.split == .development }
        let held = table.rows.filter { $0.split == .heldout }
        let calibration = held.filter { !Self.isTest($0, seed: request.seed) }
        let test = held.filter { Self.isTest($0, seed: request.seed) }
        for (name, side) in [("fit", fit), ("calibration", calibration), ("test", test)]
        where Set(side.map(\.label)).count < 2 {
            throw Failure.emptySide(name)
        }
        let trials = request.grid.map {
            Trial(
                value: $0, fit: Self.score(fit, at: $0, request),
                calibration: Self.score(calibration, at: $0, request))
        }
        let choice = Self.choose(trials, request)
        let chosen = choice.index.map { trials[$0] }
        let digest = SHA256.hash(data: tableData).map { String(format: "%02x", $0) }.joined()
        record = Record(
            schemaVersion: Self.schemaVersion, parameter: request.parameter, feature: request.feature,
            direction: request.direction, grid: request.grid, objective: Self.objective,
            falseFlagBound: request.falseFlagBound, seed: request.seed, tableDigest: "sha256:" + digest,
            featureSpecVersion: table.featureSpecVersion, engine: request.engine, trials: trials,
            verdict: choice.verdict, chosen: chosen?.value,
            neighbours: choice.index.map { Self.neighbours(of: $0, count: trials.count).map { trials[$0] } }
                ?? [],
            marginSteps: request.marginSteps, cliffTolerance: request.cliffTolerance,
            test: chosen.map { Self.score(test, at: $0.value, request) }, id: ""
        ).identified()
    }

    /// The sweep's JSON, sorted keys so the same inputs always give the same bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(record)
    }

    /// The lines a person reads: the verdict, the chosen value with its neighbours, and the test score once.
    public var report: [String] {
        var lines = ["\(record.parameter): \(record.verdict.rawValue) (record \(record.id))"]
        guard let chosen = record.chosen else {
            lines.append(
                record.verdict == .cliff
                    ? "the optimum is a cliff; add --margin-steps" : "no grid value holds the bound")
            return lines
        }
        lines.append("chosen \(chosen) after \(record.trials.count) trials")
        for neighbour in record.neighbours {
            lines.append("neighbour \(neighbour.value): missed \(neighbour.calibration.missed)")
        }
        if let test = record.test {
            lines.append("test: missed \(test.missed), false flags \(test.falseFlags) (scored once)")
        }
        return lines
    }

    static func isTest(_ row: FitTableRow, seed: String) -> Bool {
        CorpusSplit.digest("\(seed):\(row.ordinal)") % 2 == 1
    }

    static func flagged(_ row: FitTableRow, at value: Double, _ request: Request) -> Bool {
        let feature = row.features[request.feature]
        return request.direction == .atOrBelow ? feature <= value : feature >= value
    }

    static func score(_ rows: [FitTableRow], at value: Double, _ request: Request) -> Score {
        let wrong = rows.filter { $0.label == .wrong }
        let right = rows.filter { $0.label == .right }
        func share(_ count: Int, of total: Int) -> Double { total == 0 ? 0 : Double(count) / Double(total) }
        return Score(
            missed: share(wrong.count { !flagged($0, at: value, request) }, of: wrong.count),
            falseFlags: share(right.count { flagged($0, at: value, request) }, of: right.count),
            rows: rows.count)
    }

    /// The feasible trial with the fewest misses on calibration, the strictest on a tie; a cliff is refused without a margin.
    static func choose(_ trials: [Trial], _ request: Request) -> (index: Int?, verdict: Verdict) {
        let feasible = trials.indices.filter { trials[$0].fit.falseFlags <= request.falseFlagBound }
        let best = feasible.min { lhs, rhs in
            let (left, right) = (trials[lhs], trials[rhs])
            if left.calibration.missed != right.calibration.missed {
                return left.calibration.missed < right.calibration.missed
            }
            return request.direction == .atOrBelow ? left.value < right.value : left.value > right.value
        }
        guard let best else { return (nil, .infeasible) }
        let around = neighbours(of: best, count: trials.count)
        let cliff = around.contains {
            trials[$0].calibration.missed - trials[best].calibration.missed > request.cliffTolerance
                || trials[$0].fit.falseFlags > request.falseFlagBound
        }
        guard cliff else { return (best, .chosen) }
        guard request.marginSteps > 0 else { return (nil, .cliff) }
        let safe = around.filter { trials[$0].fit.falseFlags <= request.falseFlagBound }
        let flatter = safe.min {
            abs(trials[$0].calibration.missed - trials[best].calibration.missed)
                < abs(trials[$1].calibration.missed - trials[best].calibration.missed)
        }
        guard let flatter else { return (nil, .cliff) }
        let direction = flatter >= best ? 1 : -1
        let distance = direction > 0 ? trials.count - 1 - best : best
        let steps = min(request.marginSteps, distance)
        return (best + direction * steps, .chosen)
    }

    static func neighbours(of index: Int, count: Int) -> [Int] {
        [index - 1, index + 1].filter { $0 >= 0 && $0 < count }
    }
}
