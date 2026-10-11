import Foundation

/// Opt-in JSON records carry existing grid outcomes without changing their assertions.
package enum QualityGridReport {
    private static let isEnabled = ProcessInfo.processInfo.environment["UTTRFLOW_QUALITY_REPORT"] == "1"

    private struct Record: Encodable {
        let version = 1
        let suite: String
        let id: String
        let passed: Bool?
        let failed: Int?
        let allowed: Int?
        let measurements: [String: Int]
    }

    package static func emit(
        suite: String, id: String, passed: Bool?, failed: Int? = nil, allowed: Int? = nil,
        measurements: [String: Int] = [:], environment: [String: String]? = nil,
        write: (String) -> Void = { print($0) }
    ) throws {
        guard environment.map({ $0["UTTRFLOW_QUALITY_REPORT"] == "1" }) ?? isEnabled else { return }
        let record = Record(
            suite: suite, id: id, passed: passed, failed: failed, allowed: allowed,
            measurements: measurements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        write("QUALITY_GRID " + String(decoding: data, as: UTF8.self))
    }
}
