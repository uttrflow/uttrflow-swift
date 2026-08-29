import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore

/// What the collector counts, what it refuses to count, and what it costs a dictation.
@Suite("Collecting telemetry")
struct TelemetryCollectorTests {
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

    /// The table has `check (cancelled_count <= dictation_count)`. Because a cancellation
    /// is recorded as a dictation that was cancelled rather than as its own event, there is
    /// no sequence of calls that can breach it.
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

    /// A cancelled dictation never produced text, so timing it to "when the text appeared"
    /// would be timing something that did not happen.
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

    /// Uttrflow must have one definition of "typical", not two.
    ///
    /// ``StageLatency/typical`` is the median the debug panel and the evaluation harness
    /// already show, and it is documented as the upper of the two middle samples. The
    /// percentile used for the wire is indexed so that at 0.5 it lands on exactly that
    /// sample. If somebody changes either, this fails and they have to decide which
    /// median Uttrflow means — rather than shipping both.
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

    /// The pipeline times correction and expansion too, and this collector is handed
    /// them like everything else. They go no further, because the server has no name
    /// for them — see ``TelemetryStage/init(_:)``.
    @Test("a stage the server cannot name is measured but not reported")
    func unreportableStagesAreDropped() throws {
        let collector = Telemetry.collector()
        dictate(collector)
        collector.record(.init(stage: .correction, duration: .milliseconds(4), succeeded: true))
        collector.record(.init(stage: .expansion, duration: .milliseconds(2), succeeded: false))

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.stages.isEmpty)
    }

    /// The pipeline already times every stage through
    /// ``MetricsRecording/measuring(_:clock:isolation:operation:)``. Conforming means it
    /// needs no telemetry-specific code to feed this.
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
        // The oldest samples were overwritten, so the smallest survivor is not the first
        // millisecond recorded.
        #expect(try #require(report.latencyP50Ms) > 1)
    }

    /// A clock that steps backwards mid-stage would otherwise produce a negative duration,
    /// which the server refuses — costing the whole report over one bad measurement.
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

    /// A caller polling on a timer asks for a report far more often than one exists. If
    /// asking consumed the window regardless, a clock that had not advanced would quietly
    /// take the dictations with it.
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

/// The opt-out, tested as the thing the user was promised rather than as a flag.
///
/// "Off" has to mean *nothing is collected*. An implementation that gathered everything and
/// dropped it at the door would pass a test that only checked what was sent, and would
/// still be a version of Uttrflow that had the user's numbers in memory after they said no.
/// So these tests look at what the collector is holding, not only at what comes out of it.
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

    /// The test that separates "not collected" from "collected and discarded".
    ///
    /// Everything above was recorded while switched off. Switching back on cannot make it
    /// reappear, because it was never written down — had the collector merely withheld it
    /// at reporting time, the counters would still be sitting there and this report would
    /// arrive full of dictations the user had asked Uttrflow not to watch.
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
