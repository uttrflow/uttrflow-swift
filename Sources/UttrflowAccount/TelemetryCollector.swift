public import UttrflowCore
public import struct Foundation.Date

public import class Foundation.ProcessInfo

import struct Synchronization.Mutex

/// How a dictation ended.
///
/// Three answers rather than a `succeeded` boolean, because the server counts cancelled
/// and failed separately and they mean opposite things about the product: one is the user
/// changing their mind, the other is Uttrflow letting them down.
public enum DictationOutcome: Sendable, Equatable, CaseIterable {
    case completed
    /// The user abandoned it. Never counted as a failure, and never a latency sample —
    /// there was no text appearing to measure to.
    case cancelled
    /// Uttrflow could not finish it.
    case failed
}

/// The running totals between one report and the next.
///
/// Everything the dictation path can say about itself, accumulated as integers. Note what
/// the methods below will not accept: there is no parameter of any text type on any of
/// them, so the privacy line is held at the point of collection and not merely at the
/// point of upload. A caller cannot hand this object a transcript to discard, because
/// there is no signature that takes one.
///
/// ## Why the dictation never waits
///
/// Every recording method is **synchronous and non-`async`**. That is the guarantee, and
/// it is one the compiler enforces rather than one this comment asserts: a function with
/// no `async` in its signature has no suspension point, so a dictation calling it cannot
/// be parked behind a network request, a disk write, or another actor's queue. The work
/// each call does is a handful of integer additions and at most one array element written
/// in place, under an uncontended `Mutex` — bounded, allocation-free once warm, and
/// nowhere near the millisecond the user could notice.
///
/// Sending is the other half of that promise and lives in ``TelemetryService``, which is
/// the only `async` thing here and is never called from the dictation path.
public final class TelemetryCollector: MetricsRecording {
    /// How many latency samples any one series keeps.
    ///
    /// A cap rather than an unbounded array, because the window between reports is as long
    /// as the app has been running and a user who never quits would otherwise grow this
    /// without limit. Five hundred and twelve samples put a percentile within a fraction of
    /// a millisecond of the true one, and cost four kilobytes.
    public static let sampleCapacity = 512

    private let state: Mutex<State>

    /// - Parameters:
    ///   - isEnabled: Whether to collect anything at all. Deliberately without a default:
    ///     a build that starts reporting because somebody omitted an argument is exactly
    ///     the accident this whole module is arranged to prevent, so the decision has to be
    ///     written down at the call site. Persisting the user's choice between launches is
    ///     the settings layer's job, not this one's.
    ///   - appVersion: This build, as three numbers.
    ///   - osVersionMajor: The macOS major version.
    ///   - startedAt: When this reporting window opened.
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

    /// Turns collection on or off.
    ///
    /// Switching off discards everything gathered so far in the same breath. Keeping it
    /// "just in case they change their mind" would mean the app was holding data the user
    /// had just asked it not to have.
    public func setEnabled(_ enabled: Bool, at moment: Date) {
        state.withLock { state in
            state.reset(at: moment)
            state.isEnabled = enabled
        }
    }

    /// Records one dictation.
    ///
    /// - Parameters:
    ///   - outcome: How it ended.
    ///   - language: Which of the languages this app will name it was in.
    ///   - audio: How long the microphone was open.
    ///   - processing: How long the user waited between finishing speaking and seeing
    ///     text. Both summed into the total and kept as a latency sample, so the two
    ///     numbers the server receives cannot disagree about what was measured.
    ///   - charactersInserted: How many characters were inserted. Never which.
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

    /// Records one stage of one dictation, as ``MetricsRecording/measuring(_:clock:isolation:operation:)``
    /// already produces it.
    ///
    /// Conforming to ``MetricsRecording`` rather than inventing a second way to time things
    /// means the pipeline needs no telemetry-specific code at all: whatever already
    /// measures a stage feeds this too. The requirement is `async` and this witness is not,
    /// which is allowed and is the point — the caller gets no suspension point.
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

    /// The report for the window that just closed, and a fresh window from here.
    ///
    /// Named `take` because it consumes: what it returns is no longer held, so a caller
    /// that drops it loses it. ``TelemetryService`` puts it straight into the outbox.
    ///
    /// It consumes *only* what it returns. A window that produced no report keeps running,
    /// so a caller that polls on a timer does not quietly throw away the dictations in a
    /// window the clock happened to make unreportable.
    ///
    /// - Parameter moment: When the window closed.
    /// - Returns: The report, or `nil` when there is nothing to say — collection is off,
    ///   no dictation happened, or the clock did not advance.
    public func takeReport(endedAt moment: Date) -> TelemetryReport? {
        state.withLock { state in
            guard state.isEnabled, let report = state.report(endedAt: moment) else { return nil }
            state.reset(at: moment)
            return report
        }
    }

    /// The single door every accumulation goes through, and therefore the single place the
    /// opt-out is enforced.
    ///
    /// One guard rather than one per method: a recording method added later cannot forget
    /// to check, because `state` is private and this is the only way to write to it.
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
        var isEnabled: Bool
        let appVersion: TelemetryReport.AppVersion
        let osVersionMajor: Int?
        var windowStartedAt: Date

        var dictationCount = 0
        var cancelledCount = 0
        var failureCount = 0
        var audioTotalMs = 0
        var processingTotalMs = 0
        var charactersInserted = 0
        var languages: [TelemetryLanguage: Int] = [:]
        var latencies = Samples()
        var stageLatencies: [TelemetryStage: Samples] = [:]
        var stageFailures: [TelemetryStage: Int] = [:]

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

        /// Empties every counter and opens a new window.
        ///
        /// Assigning a whole fresh value rather than zeroing fields one by one, so a
        /// counter added later cannot be left behind holding the previous window's data —
        /// or, when the user has just opted out, data they asked the app to forget.
        mutating func reset(at moment: Date) {
            self = State(
                isEnabled: isEnabled, appVersion: appVersion, osVersionMajor: osVersionMajor,
                windowStartedAt: moment)
        }
    }

    /// A fixed-size window of the most recent samples.
    ///
    /// Overwrites the oldest when full rather than refusing new ones: the interesting
    /// latencies are the recent ones, and a buffer that stops accepting samples would
    /// report yesterday's percentiles for ever. Writing in place keeps the cost of a sample
    /// constant, which matters because the caller is a dictation.
    struct Samples: Sendable, Equatable {
        private var values: [Int] = []
        private var next = 0

        mutating func append(_ milliseconds: Int) {
            let value = max(milliseconds, 0)
            if values.count < TelemetryCollector.sampleCapacity {
                values.append(value)
            } else {
                values[next] = value
                next = (next + 1) % TelemetryCollector.sampleCapacity
            }
        }

        /// The sample at `fraction` of the way through, or `nil` when nothing was measured.
        ///
        /// `nil` rather than zero, and the distinction is the same one ``StageLatency``
        /// draws: a stage nothing timed is not a stage that was instant, and the server's
        /// column is nullable precisely so the difference survives.
        ///
        /// The index is `count * fraction`, which at `0.5` is `count / 2` — exactly the
        /// median ``StageLatency/typical`` reports. Uttrflow therefore has one definition of
        /// its own median rather than two that drift apart, and
        /// `TelemetryCollectorTests` checks that they still agree.
        func percentile(_ fraction: Double) -> Int? {
            let sorted = values.sorted()
            guard let last = sorted.indices.last else { return nil }
            return sorted[min(last, Int(Double(sorted.count) * fraction))]
        }
    }
}

extension Duration {
    /// Whole milliseconds, never negative.
    ///
    /// The floor at zero is not defensive tidiness: a clock that steps backwards mid-stage
    /// would otherwise produce a negative duration, and the server's `durationMs` refuses
    /// one — costing the whole report rather than the one bad measurement.
    var inWholeMilliseconds: Int {
        max(Int((inSeconds * 1000).rounded()), 0)
    }
}
