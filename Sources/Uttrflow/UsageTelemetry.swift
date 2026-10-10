// The app's usage telemetry: counts dictations as they end and sends them on a timer, never on the dictation path.

import Foundation
import Synchronization
import UttrflowAccount
import UttrflowCore
import UttrflowPipeline

/// Owns the telemetry service, feeds it each finished dictation and flushes it hourly. See `Docs/account-telemetry.md`.
@MainActor
final class UsageTelemetry {
    /// How often owed reports are sent.
    static let flushInterval = Duration.seconds(3600)

    /// How long quitting waits for a flush before giving up on it.
    static let quitBudget = Duration.seconds(3)

    /// The collector, outbox and ledger.
    let service: TelemetryService
    /// When the dictation under way stopped listening, which is where the user's wait begins.
    private var waitStarted: ContinuousClock.Instant?
    /// Whether a non-terminal pipeline state has arrived and still needs an outcome.
    private var dictationIsInProgress = false
    /// Whether an account change is waiting to discard the current dictation's eventual outcome.
    private var discardingCurrentDictation = false
    /// Buffers state events until the pipeline confirms which dictation crossed the account boundary.
    private var awaitingAccountSwitchState = false
    /// Pipeline events at or below the account-boundary snapshot belong to the previous account.
    private var discardThroughRevision: UInt64?
    /// Revisioned events delivered while the boundary snapshot is being read.
    private var pendingAccountSwitchStates:
        [(state: DictationState, language: LanguageCode?, revision: UInt64, instant: ContinuousClock.Instant)] =
            []
    /// Gates stage measurements from a dictation that was already running at sign-out.
    private let stageRecorder: AccountBoundaryMetricsRecorder
    /// The hourly flush.
    private var timer: Task<Void, Never>?
    private var interval = UsageTelemetry.flushInterval

    /// A service collecting only while `isEnabled`, posting through `sender`.
    init(isEnabled: Bool, sender: any TelemetrySending, version: String?, now: Date = Date()) {
        let collector = TelemetryCollector(
            isEnabled: isEnabled, appVersion: Self.appVersion(from: version), startedAt: now)
        let service = TelemetryService(collector: collector, sender: sender)
        self.service = service
        stageRecorder = AccountBoundaryMetricsRecorder(collector: service.recorder)
    }

    /// The recorder the pipeline's stage timings also go to.
    var recorder: any MetricsRecording { stageRecorder }

    /// `26.0926.0` as three numbers; anything unreadable is `0.0.0` rather than a guess.
    static func appVersion(from text: String?) -> TelemetryReport.AppVersion {
        let parts = (text ?? "").split(separator: ".").map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else {
            return TelemetryReport.AppVersion(major: 0, minor: 0, patch: 0)
        }
        return TelemetryReport.AppVersion(major: major, minor: minor, patch: patch)
    }

    /// Counts a dictation once it has ended; synchronous and cheap, so rendering never waits on it.
    func observe(
        _ state: DictationState, language: LanguageCode?, pipelineRevision: UInt64? = nil,
        at instant: ContinuousClock.Instant = .now
    ) {
        if awaitingAccountSwitchState {
            if let pipelineRevision {
                pendingAccountSwitchStates.append((state, language, pipelineRevision, instant))
            }
            return
        }
        record(state, language: language, pipelineRevision: pipelineRevision, at: instant)
    }

    private func record(
        _ state: DictationState, language: LanguageCode?, pipelineRevision: UInt64?,
        at instant: ContinuousClock.Instant
    ) {
        if let discardThroughRevision, let pipelineRevision, pipelineRevision <= discardThroughRevision {
            return
        }
        guard !discardedOutcome(state) else { return }
        let spoken = language.map(TelemetryLanguage.init) ?? .other
        switch state {
        case .recording:
            dictationIsInProgress = true
            waitStarted = nil
        case .idle, .executed, .discarded:
            if dictationIsInProgress {
                service.recorder.recordDictation(
                    .cancelled, language: spoken, processing: waited(until: instant))
            } else {
                waitStarted = nil
            }
            dictationIsInProgress = false
        case .transcribing, .tidying, .inserting:
            dictationIsInProgress = true
            if waitStarted == nil { waitStarted = instant }
        case .inserted(let outcome):
            dictationIsInProgress = false
            service.recorder.recordDictation(
                .completed, language: spoken, audio: outcome.spokenFor ?? .zero,
                processing: waited(until: instant), charactersInserted: outcome.text.count)
        case .failed:
            dictationIsInProgress = false
            service.recorder.recordDictation(.failed, language: spoken, processing: waited(until: instant))
        }
    }

    /// How long the user has waited since listening stopped, then forgets the start.
    private func waited(until instant: ContinuousClock.Instant) -> Duration {
        defer { waitStarted = nil }
        return waitStarted.map { $0.duration(to: instant) } ?? .zero
    }

    /// Follows the Settings switch; off drops everything collected and everything still owed.
    func setEnabled(_ enabled: Bool) {
        guard enabled != service.isEnabled else { return }
        service.setEnabled(enabled, at: Date())
    }

    /// Starts the hourly flush.
    func start(every interval: Duration = UsageTelemetry.flushInterval) {
        self.interval = interval
        timer?.cancel()
        timer = Task { [service] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await service.flush(at: Date())
            }
        }
    }

    /// Discards the signed-in account's unsent window and prevents its current dictation outcome being attributed later.
    func discardPendingForAccountSwitch(
        pipelineState: @escaping @Sendable () async -> DictationStateSnapshot?
    ) -> Task<Void, Never> {
        let restartInterval = timer == nil ? nil : interval
        awaitingAccountSwitchState = true
        discardingCurrentDictation = false
        dictationIsInProgress = false
        waitStarted = nil
        timer?.cancel()
        timer = nil
        stageRecorder.beginBoundary()
        service.discardPending(at: Date())
        return Task { [weak self] in
            let snapshot = await pipelineState()
            guard let self else { return }
            awaitingAccountSwitchState = false
            discardThroughRevision = snapshot?.revision
            discardingCurrentDictation = snapshot?.state.isBusy ?? false
            stageRecorder.finishBoundary(afterGeneration: snapshot?.generation)
            dictationIsInProgress = false
            waitStarted = nil
            let pending = pendingAccountSwitchStates
            pendingAccountSwitchStates.removeAll()
            if let boundary = snapshot?.revision {
                for event in pending where event.revision > boundary {
                    record(
                        event.state, language: event.language, pipelineRevision: event.revision,
                        at: event.instant)
                }
            }
            if let restartInterval { start(every: restartInterval) }
        }
    }

    /// Suppresses the old dictation through its terminal state, then reopens stage collection.
    private func discardedOutcome(_ state: DictationState) -> Bool {
        guard discardingCurrentDictation else { return false }
        switch state {
        case .recording, .transcribing, .tidying, .inserting:
            return true
        case .idle, .discarded, .inserted, .executed, .failed:
            discardingCurrentDictation = false
            return true
        }
    }

    /// Stops the timer and sends what is owed, giving up after ``quitBudget``.
    func flushBeforeQuitting() async {
        timer?.cancel()
        timer = nil
        let service = service
        _ = try? await withStageTimeout(Self.quitBudget, clock: ContinuousClock()) {
            await service.flush(at: Date())
        }
    }
}

private final class AccountBoundaryMetricsRecorder: MetricsRecording, Sendable {
    private struct State: Sendable {
        var resolvingBoundary = false
        var minimumGeneration: Int?
    }

    private let collector: TelemetryCollector
    private let state = Mutex(State())

    init(collector: TelemetryCollector) {
        self.collector = collector
    }

    func beginBoundary() {
        state.withLock { $0.resolvingBoundary = true }
    }

    func finishBoundary(afterGeneration generation: Int?) {
        state.withLock { state in
            // No pipeline means no dictation crossed the boundary, so only the pause is lifted.
            if let generation { state.minimumGeneration = generation }
            state.resolvingBoundary = false
        }
    }

    func record(_ measurement: StageMeasurement) async {
        state.withLock { mode in
            guard !mode.resolvingBoundary else { return }
            if let minimumGeneration = mode.minimumGeneration {
                guard let generation = measurement.generation, generation > minimumGeneration else { return }
            }
            collector.record(measurement)
        }
    }
}
