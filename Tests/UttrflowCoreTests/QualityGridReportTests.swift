import Foundation
import Testing
import UttrflowTestSupport

@Suite("Structured quality grid reports")
struct QualityGridReportTests {
    @Test("reporting is opt-in and leaves the normal test output alone")
    func disabledByDefault() throws {
        var output: [String] = []
        try QualityGridReport.emit(
            suite: "fixture", id: "case", passed: true, environment: [:], write: { output.append($0) })
        #expect(output.isEmpty)
    }

    @Test("a gated bucket exports its outcome, failures and binding allowance in one JSON line")
    func bucketProtocol() throws {
        var output: [String] = []
        try QualityGridReport.emit(
            suite: "fixture", id: "bucket", passed: true, failed: 2, allowed: 3,
            measurements: ["total": 8], environment: ["UTTRFLOW_QUALITY_REPORT": "1"],
            write: { output.append($0) })
        let line = try #require(output.first)
        #expect(output.count == 1)
        #expect(line.hasPrefix("QUALITY_GRID "))
        let payload = Data(line.dropFirst("QUALITY_GRID ".count).utf8)
        let decoded = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(decoded["version"] as? Int == 1)
        #expect(decoded["passed"] as? Bool == true)
        #expect(decoded["failed"] as? Int == 2)
        #expect(decoded["allowed"] as? Int == 3)
        #expect(decoded["measurements"] as? [String: Int] == ["total": 8])
    }

    @Test("diagnostics have no pass verdict and escaped IDs stay on one line")
    func diagnosticProtocol() throws {
        var output: [String] = []
        try QualityGridReport.emit(
            suite: "fixture", id: "line\n\"quoted\"", passed: nil, measurements: ["clip": 10],
            environment: ["UTTRFLOW_QUALITY_REPORT": "1"], write: { output.append($0) })
        let line = try #require(output.first)
        #expect(!line.contains("\n"))
        let payload = Data(line.dropFirst("QUALITY_GRID ".count).utf8)
        let decoded = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(decoded["passed"] == nil)
        #expect(decoded["id"] as? String == "line\n\"quoted\"")
        #expect(decoded["measurements"] as? [String: Int] == ["clip": 10])
    }
}
