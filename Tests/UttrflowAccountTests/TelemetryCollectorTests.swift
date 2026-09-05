// Tests for TelemetryCollector: what it counts, what it refuses to count, and the opt-out.

import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore

/// What the collector counts, what it refuses to count, and what it costs a dictation.
@Suite("Collecting telemetry")
struct TelemetryCollectorTests {
    /// Records one dictation, with every measurement defaulted to nothing.
    private func dictate(
        _ collector: TelemetryCollector, _ outcome: DictationOutcome = .completed,
        language: TelemetryLanguage = .english, audio: Duration = .zero,
        processing: Duration = .zero, characters: Int = 0
    ) {
        collector.recordDictation(
            outcome, language: language, audio: audio, processing: processing,
            charactersInserted: characters)
    }

    @Test("counts dictations, cancellations and failures separately")
    func countsEachOutcome() throws {
        let collector = Telemetry.collector()
        dictate(collector, .completed)
        dictate(collector, .cancelled)
        dictate(collector, .failed)

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.dictationCount == 3)
        #expect(report.cancelledCount == 1)
        #expect(report.failureCount == 1)
    }

    /// A cancellation is recorded as a cancelled dictation, so `cancelled_count <= dictation_count` holds.
    @Test("a cancellation is always also a dictation, so the server's check cannot fail")
    func cancellationsCannotOutnumberDictations() throws {
        let collector = Telemetry.collector()
        for _ in 0..<5 { dictate(collector, .cancelled) }

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.cancelledCount == 5)
        #expect(report.dictationCount == 5)
    }

    @Test("sums durations and characters, and counts languages")
    func sumsTheNumbers() throws {
        let collector = Telemetry.collector()
        dictate(collector, audio: .seconds(3), processing: .milliseconds(400), characters: 50)
        dictate(
            collector, language: .hindi, audio: .seconds(2), processing: .milliseconds(600), characters: 30)

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.audioTotalMs == 5_000)
        #expect(report.processingTotalMs == 1_000)
        #expect(report.charactersInserted == 80)
        #expect(report.languages.map(\.language) == [.english, .hindi])
        #expect(report.languages.allSatisfy { $0.dictationCount == 1 })
    }

    /// A cancelled dictation produces no text, so there is no "when the text appeared" to time.
    @Test("only completed dictations contribute latency samples")
    func onlyCompletionsAreTimed() throws {
        let collector = Telemetry.collector()
        dictate(collector, .cancelled, processing: .seconds(30))
        dictate(collector, .failed, processing: .seconds(30))

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.latencyP50Ms == nil)
        // The waiting still happened, so the total still counts it.
        #expect(report.processingTotalMs == 60_000)
    }

    @Test("reports percentiles once something has been timed")
    func reportsPercentiles() throws {
        let collector = Telemetry.collector()
        for milliseconds in [100, 200, 300, 400, 900] {
            dictate(collector, processing: .milliseconds(milliseconds))
        }

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.latencyP50Ms == 300)
        #expect(report.latencyP90Ms == 900)
        #expect(report.latencyP99Ms == 900)
    }

    /// The wire p50 is indexed to land on ``StageLatency/typical``, so there is one definition of "typical".
    @Test("the p50 sent to the server is the same median the app shows the user")
    func medianAgreesWithStageLatency() throws {
        for count in 1...12 {
            let durations = (1...count).map { Duration.milliseconds($0 * 10) }
            let collector = Telemetry.collector()
            let measurements = durations.map {
                StageMeasurement(stage: .transcription, duration: $0, succeeded: true)
            }
            for measurement in measurements { collector.record(measurement) }
            dictate(collector)

            let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
            let stage = try #require(report.stages.first)
            let core = try #require(StageLatency.summarise(measurements, stage: .transcription))

            #expect(
                stage.latencyP50Ms == core.typical.inWholeMilliseconds,
                "with \(count) samples the two medians disagree")
        }
    }

    @Test("records which stage failed and how slow the ones that worked were")
    func recordsStageOutcomes() throws {
        let collector = Telemetry.collector()
        dictate(collector, .failed)
        collector.record(.init(stage: .transcription, duration: .milliseconds(500), succeeded: true))
        collector.record(.init(stage: .insertion, duration: .milliseconds(10), succeeded: false))

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.stages.map(\.stage) == [.insertion, .transcription])
        #expect(report.stages.map(\.failureCount) == [1, 0])
        // A stage that only ever failed has no latency, which is not the same as being fast.
        #expect(report.stages[0].latencyP50Ms == nil)
        #expect(report.stages[1].latencyP50Ms == 500)
    }

    /// Correction and expansion are timed but go no further, because the server has no name for them.
    @Test("a stage the server cannot name is measured but not reported")
    func unreportableStagesAreDropped() throws {
        let collector = Telemetry.collector()
        dictate(collector)
        collector.record(.init(stage: .correction, duration: .milliseconds(4), succeeded: true))
        collector.record(.init(stage: .expansion, duration: .milliseconds(2), succeeded: false))

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.stages.isEmpty)
    }

    /// Conforming to ``MetricsRecording`` means the pipeline feeds this with no telemetry-specific code.
    @Test("plugs into the timing the pipeline already does")
    func worksAsAMetricsRecorder() async throws {
        let collector = Telemetry.collector()
        let recorder: any MetricsRecording = collector
        let clock = ContinuousClock()

        let result = await recorder.measuring(.transformation, clock: clock) { 7 }
        #expect(result == 7)
        dictate(collector)

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.stages.map(\.stage) == [.tidying])
    }

    // MARK: - Bounds

    /// A user who never quits would otherwise accumulate one sample per dictation for ever.
    @Test("keeps a bounded number of samples however long the app runs")
    func samplesAreBounded() throws {
        let collector = Telemetry.collector()
        let extra = 50
        for index in 0..<(TelemetryCollector.sampleCapacity + extra) {
            dictate(collector, processing: .milliseconds(index + 1))
        }

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.dictationCount == TelemetryCollector.sampleCapacity + extra)
        // The oldest samples are overwritten, so the smallest survivor is not the first millisecond recorded.
        #expect(try #require(report.latencyP50Ms) > 1)
    }

    /// A clock stepping backwards mid-stage would give a negative duration, which the server refuses.
    @Test("never reports a negative duration")
    func negativeDurationsBecomeZero() throws {
        let collector = Telemetry.collector()
        dictate(collector, audio: .seconds(-5), processing: .seconds(-1))

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.audioTotalMs == 0)
        #expect(report.latencyP50Ms == 0)
    }

    // MARK: - Windows

    @Test("starts a fresh window after a report is taken")
    func takingAReportResetsTheWindow() throws {
        let collector = Telemetry.collector()
        dictate(collector)
        _ = collector.takeReport(endedAt: Telemetry.anHourLater)

        #expect(collector.takeReport(endedAt: Telemetry.anHourLater.addingTimeInterval(3600)) == nil)

        dictate(collector)
        let second = try #require(
            collector.takeReport(endedAt: Telemetry.anHourLater.addingTimeInterval(7200)))
        #expect(second.dictationCount == 1)
        #expect(second.windowStartedAt == Telemetry.anHourLater)
    }

    @Test("says nothing when nothing was dictated")
    func idleWindowsProduceNoReport() {
        #expect(Telemetry.collector().takeReport(endedAt: Telemetry.anHourLater) == nil)
    }

    /// A timer polls far more often than a report exists; asking must not consume an unadvanced window.
    @Test("keeps the window when it has no report to give")
    func nothingIsLostWhenThereIsNoReport() throws {
        let collector = Telemetry.collector()
        dictate(collector, characters: 42)

        // The clock has not advanced, so there is no reportable window yet.
        #expect(collector.takeReport(endedAt: Telemetry.noon) == nil)

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.charactersInserted == 42)
        #expect(report.windowStartedAt == Telemetry.noon)
    }

    @Test("asks the system for the macOS version so the app need not")
    func knowsTheOSVersion() throws {
        #expect(TelemetryCollector.currentOSMajorVersion > 0)

        let collector = TelemetryCollector(
            isEnabled: true, appVersion: Telemetry.version, startedAt: Telemetry.noon)
        dictate(collector)

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.osVersionMajor == TelemetryCollector.currentOSMajorVersion)
    }
}

/// "Off" means nothing is collected: these tests inspect what the collector holds, not only what it emits.
@Suite("Turning telemetry off")
struct TelemetryOptOutTests {
    @Test("collects nothing at all while switched off")
    func collectsNothing() {
        let collector = Telemetry.collector(isEnabled: false)
        for index in 0..<100 {
            collector.recordDictation(
                .completed, language: .hindi, audio: .seconds(9), processing: .seconds(2),
                charactersInserted: index)
            collector.record(.init(stage: .transcription, duration: .seconds(1), succeeded: false))
        }

        #expect(!collector.isEnabled)
        #expect(collector.takeReport(endedAt: Telemetry.anHourLater) == nil)
    }

    /// Nothing recorded while off is written down, so switching back on has nothing to resurface.
    @Test("nothing recorded while off can reappear once it is switched back on")
    func nothingIsHeldBack() throws {
        let collector = Telemetry.collector(isEnabled: false)
        for _ in 0..<100 {
            collector.recordDictation(.completed, language: .hindi, charactersInserted: 500)
        }

        collector.setEnabled(true, at: Telemetry.noon)
        #expect(collector.takeReport(endedAt: Telemetry.anHourLater) == nil)

        collector.recordDictation(.completed, language: .english, charactersInserted: 1)
        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.dictationCount == 1)
        #expect(report.charactersInserted == 1)
        #expect(report.languages.map(\.language) == [.english])
    }

    /// Switching off is not "stop counting from here"; it is "forget what you counted".
    @Test("switching off discards what had already been counted")
    func switchingOffForgets() {
        let collector = Telemetry.collector()
        for _ in 0..<10 { collector.recordDictation(.completed, language: .english) }

        collector.setEnabled(false, at: Telemetry.noon)
        collector.setEnabled(true, at: Telemetry.noon)

        #expect(collector.takeReport(endedAt: Telemetry.anHourLater) == nil)
    }
}
