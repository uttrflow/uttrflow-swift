// The app's usage telemetry: counts dictations as they end and sends them on a timer, never on the dictation path.

import Foundation
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
    /// The hourly flush.
    private var timer: Task<Void, Never>?

    /// A service collecting only while `isEnabled`, posting through `sender`.
    init(isEnabled: Bool, sender: any TelemetrySending, version: String?, now: Date = Date()) {
        let collector = TelemetryCollector(
            isEnabled: isEnabled, appVersion: Self.appVersion(from: version), startedAt: now)
        service = TelemetryService(collector: collector, sender: sender)
    }

    /// The recorder the pipeline's stage timings also go to.
    var recorder: any MetricsRecording { service.recorder }

    /// `26.0926.0` as three numbers; anything unreadable is `0.0.0` rather than a guess.
    static func appVersion(from text: String?) -> TelemetryReport.AppVersion {
        let parts = (text ?? "").split(separator: ".").map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else {
            return TelemetryReport.AppVersion(major: 0, minor: 0, patch: 0)
        }
        return TelemetryReport.AppVersion(major: major, minor: minor, patch: patch)
    }

    /// Counts a dictation once it has ended; synchronous and cheap, so rendering never waits on it.
    func observe(_ state: DictationState, language: LanguageCode?, at instant: ContinuousClock.Instant = .now)
    {
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
        timer?.cancel()
        timer = Task { [service] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await service.flush(at: Date())
            }
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
