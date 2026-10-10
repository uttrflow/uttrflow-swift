// Tests for UsageTelemetry: what a finished dictation adds, the switch, and the flushes.

import Foundation
import Testing
import UttrflowAccount
import UttrflowCore
import UttrflowPipeline

@testable import Uttrflow

/// Drives the app's telemetry with states a pipeline would send, and a sender that keeps reports.
@MainActor
@Suite("Usage telemetry in the app")
struct UsageTelemetryTests {
    /// A dictation that inserted `text` after speaking for `spoken`.
    private func inserted(_ text: String, spoken: Duration) -> DictationState {
        .inserted(
            UttrflowPipeline.DictationOutcome(
                text: text, method: .accessibility, cleanedBy: .foundationModels, spokenFor: spoken))
    }

    @Test("reads a calendar version as three numbers, and anything else as zeros")
    func readsTheVersion() {
        #expect(UsageTelemetry.appVersion(from: "26.0926.0") == .init(major: 26, minor: 926, patch: 0))
        #expect(UsageTelemetry.appVersion(from: "26.0926") == .init(major: 0, minor: 0, patch: 0))
        #expect(UsageTelemetry.appVersion(from: nil) == .init(major: 0, minor: 0, patch: 0))
        #expect(UsageTelemetry.appVersion(from: "a.b.c") == .init(major: 0, minor: 0, patch: 0))
    }

    @Test("counts finished and failed dictations with the wait since listening stopped, and sends them")
    func countsAndSends() async throws {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(
            isEnabled: true, sender: sender, version: "26.926.0", now: Date(timeIntervalSinceNow: -60))
        let start = ContinuousClock.now
        let english = LanguageCode("en")

        usage.observe(.recording, language: english, at: start)
        usage.observe(.transcribing, language: english, at: start)
        usage.observe(.tidying, language: english, at: start + .milliseconds(100))
        usage.observe(
            inserted("Hello there.", spoken: .seconds(2)), language: english,
            at: start + .milliseconds(400))
        usage.observe(.transcribing, language: nil, at: start)
        usage.observe(
            .failed(DictationFailure(message: "no", recovery: nil, severity: .degraded)), language: nil,
            at: start)
        await usage.flushBeforeQuitting()

        let report = try #require(sender.reports.first)
        #expect(report.dictationCount == 2)
        #expect(report.failureCount == 1)
        #expect(report.charactersInserted == 12)
        #expect(report.audioTotalMs == 2000)
        #expect(report.latencyP50Ms == 400)
        #expect(report.languages.map(\.language).sorted { $0.rawValue < $1.rawValue } == [.english, .other])
    }

    @Test("counts a recording cancelled back to idle without treating it as a failure")
    func countsCancelledDictation() async throws {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(isEnabled: true, sender: sender, version: "26.926.0")
        let start = ContinuousClock.now

        usage.observe(.idle, language: nil, at: start)
        usage.observe(.recording, language: nil, at: start + .seconds(1))
        usage.observe(.idle, language: nil, at: start + .seconds(2))
        await usage.flushBeforeQuitting()

        let report = try #require(sender.reports.first)
        #expect(report.dictationCount == 1)
        #expect(report.cancelledCount == 1)
        #expect(report.failureCount == 0)
        #expect(report.processingTotalMs == 0)
        #expect(report.latencyP50Ms == nil)
    }

    @Test("switching off drops what was collected, and nothing is sent")
    func switchingOffDropsEverything() async {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(
            isEnabled: true, sender: sender, version: "26.926.0", now: Date(timeIntervalSinceNow: -60))
        usage.observe(inserted("Hi.", spoken: .seconds(1)), language: nil)

        usage.setEnabled(false)
        usage.setEnabled(false)
        await usage.flushBeforeQuitting()

        #expect(!usage.service.isEnabled)
        #expect(sender.reports.isEmpty)
    }

    @Test("a post-boundary state delivered while the snapshot is pending is replayed")
    func postBoundaryStateSurvivesSnapshotWait() async throws {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(
            isEnabled: true, sender: sender, version: "26.926.0", now: Date(timeIntervalSinceNow: -60))
        let (snapshots, yieldSnapshot) = AsyncStream<DictationStateSnapshot?>.makeStream()
        let reset = usage.discardPendingForAccountSwitch {
            for await snapshot in snapshots { return snapshot }
            return nil
        }

        usage.observe(
            inserted("new", spoken: .seconds(2)), language: LanguageCode("en"), pipelineRevision: 6)
        await usage.recorder.record(
            StageMeasurement(
                stage: .transcription, duration: .milliseconds(900), succeeded: true, generation: 4))
        yieldSnapshot.yield((revision: 5, state: DictationState.idle, generation: 4))
        await reset.value
        await usage.recorder.record(
            StageMeasurement(
                stage: .transcription, duration: .milliseconds(2000), succeeded: true, generation: 5))
        await usage.flushBeforeQuitting()

        #expect(sender.reports.first?.dictationCount == 1)
        #expect(sender.reports.first?.charactersInserted == 3)
        #expect(sender.reports.first?.stages.first?.latencyP50Ms == 2000)
    }

    @Test("a delayed terminal observer cannot reopen old-generation stage timings")
    func delayedTerminalObserverKeepsGenerationFence() async throws {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(
            isEnabled: true, sender: sender, version: "26.926.0", now: Date(timeIntervalSinceNow: -60))
        let reset = usage.discardPendingForAccountSwitch {
            (revision: 5, state: DictationState.transcribing, generation: 7)
        }
        await reset.value

        await usage.recorder.record(
            StageMeasurement(
                stage: .transcription, duration: .milliseconds(900), succeeded: true, generation: 7))
        usage.observe(
            inserted("old", spoken: .seconds(1)), language: LanguageCode("en"), pipelineRevision: 6)
        usage.observe(.recording, language: LanguageCode("en"), pipelineRevision: 7)
        await usage.recorder.record(
            StageMeasurement(
                stage: .transcription, duration: .milliseconds(3000), succeeded: true, generation: 7))
        await usage.recorder.record(
            StageMeasurement(
                stage: .transcription, duration: .milliseconds(2000), succeeded: true, generation: 8))
        usage.observe(
            inserted("new", spoken: .seconds(1)), language: LanguageCode("en"), pipelineRevision: 8)
        await usage.flushBeforeQuitting()

        let report = try #require(sender.reports.first)
        #expect(report.stages.count == 1)
        #expect(report.stages.first?.stage == .transcription)
        #expect(report.stages.first?.latencyP50Ms == 2000)
    }

    @Test("an account change drops the previous account's counts but keeps the opt-in")
    func accountSwitchDropsPreviousCounts() async throws {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(
            isEnabled: true, sender: sender, version: "26.926.0", now: Date(timeIntervalSinceNow: -60))
        usage.observe(
            inserted("previous", spoken: .seconds(1)), language: LanguageCode("en"), pipelineRevision: 1)

        await usage.discardPendingForAccountSwitch {
            (revision: 1, state: DictationState.idle, generation: 1)
        }.value
        usage.observe(.recording, language: LanguageCode("en"), pipelineRevision: 2)
        usage.observe(
            inserted("next", spoken: .seconds(1)), language: LanguageCode("en"), pipelineRevision: 3)
        await usage.flushBeforeQuitting()

        #expect(usage.service.isEnabled)
        let report = try #require(sender.reports.first)
        #expect(report.dictationCount == 1)
        #expect(report.charactersInserted == 4)
    }

    @Test("an account change with no pipeline reopens stage timings")
    func accountSwitchWithoutPipelineReopensStages() async throws {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(
            isEnabled: true, sender: sender, version: "26.926.0", now: Date(timeIntervalSinceNow: -60))

        await usage.discardPendingForAccountSwitch { nil }.value
        usage.observe(inserted("Hi.", spoken: .seconds(1)), language: nil)
        await usage.recorder.record(
            StageMeasurement(
                stage: .transcription, duration: .milliseconds(2000), succeeded: true, generation: 1))
        await usage.flushBeforeQuitting()

        let report = try #require(sender.reports.first)
        #expect(report.stages.first?.latencyP50Ms == 2000)
    }

    @Test("the timer flushes on its own")
    func theTimerFlushes() async throws {
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(
            isEnabled: true, sender: sender, version: "26.926.0", now: Date(timeIntervalSinceNow: -60))
        usage.observe(.idle, language: nil)
        usage.observe(inserted("Hi.", spoken: .seconds(1)), language: nil)
        await usage.recorder.record(
            StageMeasurement(stage: .transcription, duration: .milliseconds(2000), succeeded: true))

        usage.start(every: .milliseconds(10))
        for _ in 0..<200 where sender.reports.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        await usage.flushBeforeQuitting()
        #expect(sender.reports.count == 1)
        #expect(sender.reports[0].stages.first?.latencyP50Ms == 2000)
    }
}
