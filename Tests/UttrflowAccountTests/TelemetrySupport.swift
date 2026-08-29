import Foundation

@testable import UttrflowAccount

/// Fixed values every telemetry suite builds on, so a test says what it is testing rather
/// than how to construct a report.
enum Telemetry {
    static let noon = Date(timeIntervalSince1970: 1_700_000_000)
    static let anHourLater = noon.addingTimeInterval(3600)
    static let version = TelemetryReport.AppVersion(major: 1, minor: 4, patch: 2)

    /// A report with one dictation in it, and whatever else the test cares about.
    static func report(
        windowStartedAt: Date = noon,
        windowEndedAt: Date = anHourLater,
        osVersionMajor: Int? = 26,
        dictationCount: Int = 1,
        cancelledCount: Int = 0,
        failureCount: Int = 0,
        audioTotalMs: Int = 0,
        processingTotalMs: Int = 0,
        charactersInserted: Int = 0,
        latencyP50Ms: Int? = nil,
        latencyP90Ms: Int? = nil,
        latencyP99Ms: Int? = nil,
        languages: [TelemetryLanguage: Int] = [:],
        stages: [TelemetryReport.StageOutcome] = []
    ) -> TelemetryReport? {
        TelemetryReport(
            windowStartedAt: windowStartedAt, windowEndedAt: windowEndedAt, appVersion: version,
            osVersionMajor: osVersionMajor, dictationCount: dictationCount,
            cancelledCount: cancelledCount, failureCount: failureCount, audioTotalMs: audioTotalMs,
            processingTotalMs: processingTotalMs, charactersInserted: charactersInserted,
            latencyP50Ms: latencyP50Ms, latencyP90Ms: latencyP90Ms, latencyP99Ms: latencyP99Ms,
            languages: languages, stages: stages)
    }

    /// A collector that is switched on and has a window open at ``noon``.
    static func collector(isEnabled: Bool = true, osVersionMajor: Int? = 26) -> TelemetryCollector {
        TelemetryCollector(
            isEnabled: isEnabled, appVersion: version, osVersionMajor: osVersionMajor, startedAt: noon)
    }

    /// A collector wired to a sender that keeps everything.
    static func service(
        isEnabled: Bool = true, sender: RecordingTelemetrySender = RecordingTelemetrySender()
    ) -> (service: TelemetryService, sender: RecordingTelemetrySender) {
        (TelemetryService(collector: collector(isEnabled: isEnabled), sender: sender), sender)
    }

    /// One report's encoded form, as the JSON object a server would parse.
    static func encodedObject(_ report: TelemetryReport) -> [String: Any] {
        guard let data = report.encodedForIngest(),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
