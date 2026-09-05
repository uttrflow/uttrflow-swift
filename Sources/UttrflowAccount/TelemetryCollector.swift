// Accumulates dictation counters for telemetry without ever making a dictation wait.
public import UttrflowCore
public import struct Foundation.Date

public import class Foundation.ProcessInfo

import struct Synchronization.Mutex

/// How a dictation ended; cancelled and failed are counted apart because they mean opposite things.
public enum DictationOutcome: Sendable, Equatable, CaseIterable {
    /// Text appeared.
    case completed
    /// The user abandoned it; never a failure, and never a latency sample.
    case cancelled
    /// Uttrflow could not finish it.
    case failed
}

/// Running totals between reports; synchronous and free of text parameters. See Docs/account-telemetry.md.
public final class TelemetryCollector: MetricsRecording {
    /// How many latency samples one series keeps; 512 costs four kilobytes. See Docs/account-telemetry.md.
    public static let sampleCapacity = 512

    /// Every counter, behind one lock.
    private let state: Mutex<State>

    /// `isEnabled` has no default, so a build cannot start reporting because an argument was omitted.
    public init(
        isEnabled: Bool,
        appVersion: TelemetryReport.AppVersion,
        osVersionMajor: Int? = TelemetryCollector.currentOSMajorVersion,
        startedAt: Date
    ) {
        self.state = Mutex(
            State(
                isEnabled: isEnabled, appVersion: appVersion, osVersionMajor: osVersionMajor,
                windowStartedAt: startedAt))
    }

    /// What macOS calls itself, so the app has one less thing to wire up.
    public static var currentOSMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// Whether anything is being collected.
    public var isEnabled: Bool { state.withLock { $0.isEnabled } }

    /// Turns collection on or off, discarding everything gathered so far either way.
    public func setEnabled(_ enabled: Bool, at moment: Date) {
        state.withLock { state in
            state.reset(at: moment)
            state.isEnabled = enabled
        }
    }

    /// Records one dictation; `processing` feeds both the total and the latency sample, so the two agree.
    public func recordDictation(
        _ outcome: DictationOutcome,
        language: TelemetryLanguage,
        audio: Duration = .zero,
        processing: Duration = .zero,
        charactersInserted: Int = 0
    ) {
        mutate { state in
            state.dictationCount += 1
            state.languages[language, default: 0] += 1
            state.audioTotalMs += audio.inWholeMilliseconds
            state.processingTotalMs += processing.inWholeMilliseconds
            state.charactersInserted += max(charactersInserted, 0)
            switch outcome {
            case .completed: state.latencies.append(processing.inWholeMilliseconds)
            case .cancelled: state.cancelledCount += 1
            case .failed: state.failureCount += 1
            }
        }
    }

    /// Records one stage as ``MetricsRecording`` measures it, synchronously, so the caller never suspends.
    public func record(_ measurement: StageMeasurement) {
        mutate { state in
            // A stage the server cannot name is not sent. See ``TelemetryStage/init(_:)``.
            guard let stage = TelemetryStage(measurement.stage) else { return }
            if measurement.succeeded {
                state.stageLatencies[stage, default: Samples()].append(
                    measurement.duration.inWholeMilliseconds)
            } else {
                state.stageFailures[stage, default: 0] += 1
            }
        }
    }

    /// Takes the closed window's report, or `nil` when there is nothing to say and the window keeps running.
    public func takeReport(endedAt moment: Date) -> TelemetryReport? {
        state.withLock { state in
            guard state.isEnabled, let report = state.report(endedAt: moment) else { return nil }
            state.reset(at: moment)
            return report
        }
    }

    /// The one door every accumulation goes through, so the opt-out is enforced in one place.
    private func mutate(_ body: (inout State) -> Void) {
        state.withLock { state in
            guard state.isEnabled else { return }
            body(&state)
        }
    }
}

extension TelemetryCollector {
    /// The counters, and nothing that is not a counter.
    private struct State: Sendable {
        /// Whether anything is collected.
        var isEnabled: Bool
        /// This build.
        let appVersion: TelemetryReport.AppVersion
        /// The macOS major version, if known.
        let osVersionMajor: Int?
        /// When the current window opened.
        var windowStartedAt: Date

        /// Dictations started.
        var dictationCount = 0
        /// Dictations the user abandoned.
        var cancelledCount = 0
        /// Dictations Uttrflow could not finish.
        var failureCount = 0
        /// Milliseconds the microphone was open.
        var audioTotalMs = 0
        /// Milliseconds the user waited.
        var processingTotalMs = 0
        /// Characters inserted, counted.
        var charactersInserted = 0
        /// Dictations per language.
        var languages: [TelemetryLanguage: Int] = [:]
        /// End-to-end latency samples of completed dictations.
        var latencies = Samples()
        /// Latency samples per stage that succeeded.
        var stageLatencies: [TelemetryStage: Samples] = [:]
        /// Failures per stage.
        var stageFailures: [TelemetryStage: Int] = [:]

        /// The window's report, or `nil` when ``TelemetryReport`` refuses it.
        func report(endedAt moment: Date) -> TelemetryReport? {
            TelemetryReport(
                windowStartedAt: windowStartedAt,
                windowEndedAt: moment,
                appVersion: appVersion,
                osVersionMajor: osVersionMajor,
                dictationCount: dictationCount,
                cancelledCount: cancelledCount,
                failureCount: failureCount,
                audioTotalMs: audioTotalMs,
                processingTotalMs: processingTotalMs,
                charactersInserted: charactersInserted,
                latencyP50Ms: latencies.percentile(0.50),
                latencyP90Ms: latencies.percentile(0.90),
                latencyP99Ms: latencies.percentile(0.99),
                languages: languages,
                stages: stageOutcomes
            )
        }

        /// One entry per stage that either failed or was timed.
        private var stageOutcomes: [TelemetryReport.StageOutcome] {
            Set(stageLatencies.keys).union(stageFailures.keys).map { stage in
                let samples = stageLatencies[stage] ?? Samples()
                return TelemetryReport.StageOutcome(
                    stage: stage,
                    failureCount: stageFailures[stage] ?? 0,
                    latencyP50Ms: samples.percentile(0.50),
                    latencyP90Ms: samples.percentile(0.90)
                )
            }
        }

        /// Assigns a whole fresh value, so a counter added later cannot keep the previous window's data.
        mutating func reset(at moment: Date) {
            self = State(
                isEnabled: isEnabled, appVersion: appVersion, osVersionMajor: osVersionMajor,
                windowStartedAt: moment)
        }
    }

    /// A fixed-size ring of the most recent samples, overwritten in place so a sample costs constant time.
    struct Samples: Sendable, Equatable {
        /// The samples, at most ``sampleCapacity`` of them.
        private var values: [Int] = []
        /// Where the next sample overwrites once the ring is full.
        private var next = 0

        /// Adds a sample, floored at zero, overwriting the earliest once the ring is full.
        mutating func append(_ milliseconds: Int) {
            let value = max(milliseconds, 0)
            if values.count < TelemetryCollector.sampleCapacity {
                values.append(value)
            } else {
                values[next] = value
                next = (next + 1) % TelemetryCollector.sampleCapacity
            }
        }

        /// The sample at index `count * fraction`, or `nil` for none; 0.5 matches ``StageLatency/typical``.
        func percentile(_ fraction: Double) -> Int? {
            let sorted = values.sorted()
            guard let last = sorted.indices.last else { return nil }
            return sorted[min(last, Int(Double(sorted.count) * fraction))]
        }
    }
}

extension Duration {
    /// Whole milliseconds, floored at zero so a clock stepping backwards cannot cost the whole report.
    var inWholeMilliseconds: Int {
        max(Int((inSeconds * 1000).rounded()), 0)
    }
}
