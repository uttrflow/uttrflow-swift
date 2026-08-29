public import UttrflowCore

/// Drives one machine through the app's life and records what it cost.
///
/// Knows nothing about WhisperKit, CoreML or the clean-up router — exactly as
/// ``EvaluationRunner`` and ``TranscriptionRunner`` know nothing about what they drive.
/// That is what keeps the order of the phases, the moments memory is read at, and the
/// leak check itself testable without a 646 MB model on disk, and it is why the
/// executable that wires this up is only argument handling and printing.
public struct PerformanceProfiler: Sendable {
    /// How hard to push, and where the profile draws its lines.
    public struct Configuration: Sendable, Equatable {
        /// How many times each length is timed. Small, because the figure wanted is the
        /// median of a handful of realistic dictations, not a benchmark average.
        public var repetitions: Int
        /// How many consecutive dictations the leak check watches.
        public var leakRepetitions: Int
        /// Which length the leak check repeats. A paragraph, because that is what a
        /// person actually dictates over and over.
        public var leakLength: ProfilePassage.Length
        public var leakAllowanceBytes: Int64
        /// How often memory is read while a dictation is in flight.
        public var pollInterval: Duration

        public init(
            repetitions: Int = 3,
            leakRepetitions: Int = 10,
            leakLength: ProfilePassage.Length = .medium,
            leakAllowanceBytes: Int64 = LeakCheck.defaultAllowanceBytes,
            pollInterval: Duration = PeakMemory.defaultInterval
        ) {
            self.repetitions = repetitions
            self.leakRepetitions = leakRepetitions
            self.leakLength = leakLength
            self.leakAllowanceBytes = leakAllowanceBytes
            self.pollInterval = pollInterval
        }
    }

    /// What the profiler is doing, so an unattended run says something while a minute of
    /// speech is being decoded.
    public enum Phase: Sendable, Equatable {
        case loadingModel
        case warmingUp
        /// The leak loop, one-based.
        case repeating(dictation: Int, of: Int)
        case timing(ProfilePassage.Length, run: Int, of: Int)
        case measuringWarmLoad
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Runs the whole profile.
    ///
    /// - Parameters:
    ///   - recordings: One per length, shortest first.
    ///   - disk: What a finished install occupies. Measured by the caller, which is the
    ///     only part of this that has to know where models live.
    ///   - machine: Which Mac this is.
    ///   - read: Where a memory reading comes from. Injectable so a test can drive the
    ///     timeline and the leak check with numbers it chose.
    ///   - readCPU: Where a processor reading comes from, injectable for the same reason.
    ///     Defaults to a reader that returns `nil`, so that a caller which has not asked
    ///     for processor figures gets a report that says they were not measured rather
    ///     than one full of zeroes.
    ///   - clock: What the timings are taken against.
    ///   - onPhase: Progress, for a run that takes minutes.
    ///   - loadSpeechModel: Loads a *fresh* recogniser and says whether it worked.
    ///     Called twice — see ``ModelLoadProfile`` — so it must not hand back an
    ///     already-loaded one, or the warm figure measures nothing.
    ///   - dictate: Puts one recording through the pipeline and returns what each stage
    ///     cost. Non-throwing on purpose: a dictation that failed still took time, and
    ///     an error escaping here would abandon a profile over one bad run.
    /// - Returns: The numbers, and the leak verdict.
    public func run(
        recordings: [ProfileRecording],
        disk: DiskFootprint,
        machine: MachineDescription = .current(),
        read: @escaping @Sendable () -> MemoryReading? = MemoryFootprint.reading,
        readCPU: @escaping @Sendable () -> CPUReading? = { nil },
        clock: some Clock<Duration> = ContinuousClock(),
        onPhase: ((Phase) -> Void)? = nil,
        loadSpeechModel: () async -> Bool,
        dictate: (ProfileRecording) async -> [StageMeasurement]
    ) async -> PerformanceReport {
        var samples: [MemorySample] = []
        var peak: MemoryReading?

        let runStartedCPU = readCPU()
        let runStarted = clock.now

        /// The processor cost of one stretch, given what was read before it.
        func cpuCost(since before: CPUReading?, over elapsed: Duration) -> CPUCost? {
            CPUCost.between(before, readCPU(), wallSeconds: elapsed.inSeconds)
        }

        func sample(_ label: String) {
            if let taken = MemoryFootprint.sample(label, read: read) { samples.append(taken) }
        }

        /// Times one dictation end to end while watching memory, and folds the peak in.
        func timed(
            _ recording: ProfileRecording
        ) async -> (stages: [StageMeasurement], total: Duration, cpu: CPUCost?) {
            let beforeCPU = readCPU()
            let start = clock.now
            let (stages, observed) = await PeakMemory.observed(
                interval: configuration.pollInterval, read: read
            ) {
                await dictate(recording)
            }
            let total = start.duration(to: clock.now)
            let cpu = cpuCost(since: beforeCPU, over: total)
            if let observed {
                peak = MemoryReading(
                    footprintBytes: max(peak?.footprintBytes ?? 0, observed.footprintBytes),
                    residentBytes: max(peak?.residentBytes ?? 0, observed.residentBytes))
            }
            return (stages, total, cpu)
        }

        sample("idle, nothing loaded")

        onPhase?(.loadingModel)
        let beforeLoadCPU = readCPU()
        let firstLoadStart = clock.now
        let loaded = await loadSpeechModel()
        let firstLoad = firstLoadStart.duration(to: clock.now)
        let loadCPU = cpuCost(since: beforeLoadCPU, over: firstLoad)
        sample("speech model loaded")
        let addedBytes =
            samples.count >= 2
            ? samples[1].reading.footprintBytes - samples[0].reading.footprintBytes : nil

        // A profile of a recogniser that did not load would be a page of zeroes reported
        // as if they meant something.
        let leakRecording = recordings.first { $0.passage.length == configuration.leakLength }
        guard loaded, let leakRecording else {
            return PerformanceReport(
                machine: machine,
                modelLoad: ModelLoadProfile(
                    first: firstLoad, warm: nil, addedBytes: addedBytes, cpu: loadCPU),
                timeline: MemoryTimeline(samples: samples, peak: peak),
                leak: LeakCheck(footprints: [], allowanceBytes: configuration.leakAllowanceBytes),
                utterances: [], disk: disk,
                cpu: cpuCost(since: runStartedCPU, over: runStarted.duration(to: clock.now))
            )
        }

        // Thrown away deliberately. The first dictation of a process pays for buffers
        // every later one reuses, and counting it would make warm-up look like a leak
        // and the typical latency look like the worst case.
        onPhase?(.warmingUp)
        _ = await timed(leakRecording)
        sample("after one dictation")

        var footprintsAfterEach: [Int64] = []
        for repetition in 1...max(1, configuration.leakRepetitions) {
            onPhase?(.repeating(dictation: repetition, of: configuration.leakRepetitions))
            _ = await timed(leakRecording)
            if let after = read() { footprintsAfterEach.append(after.footprintBytes) }
        }
        sample("after \(configuration.leakRepetitions) dictations")

        var utterances: [UtteranceProfile] = []
        for recording in recordings {
            var stages: [StageMeasurement] = []
            var totals: [Duration] = []
            var costs: [CPUCost] = []
            var failures = 0
            for run in 1...max(1, configuration.repetitions) {
                onPhase?(.timing(recording.passage.length, run: run, of: configuration.repetitions))
                let (measured, total, cpu) = await timed(recording)
                stages += measured
                totals.append(total)
                if let cpu { costs.append(cpu) }
                if measured.isEmpty || measured.contains(where: { !$0.succeeded }) { failures += 1 }
            }
            guard let endToEnd = DurationSummary.over(totals, failures: failures) else { continue }
            utterances.append(
                UtteranceProfile(
                    length: recording.passage.length,
                    audioSeconds: recording.audioSeconds,
                    endToEnd: endToEnd,
                    stages: StageLatency.summarise(stages),
                    unmeasuredStages: StageLatency.unmeasuredStages(in: stages),
                    // Only the runs whose processor cost was actually read. Counting the
                    // others would divide a partial sum by a full count.
                    cpu: CPUCost.total(of: costs),
                    runs: costs.count
                ))
        }
        sample("after the length sweep")

        // Last, on purpose: a second recogniser held alongside the first would double the
        // footprint every row above reports. What it costs in seconds is the only thing
        // wanted from it.
        onPhase?(.measuringWarmLoad)
        let warmStart = clock.now
        let warmLoaded = await loadSpeechModel()
        let warmLoad = warmStart.duration(to: clock.now)

        return PerformanceReport(
            machine: machine,
            modelLoad: ModelLoadProfile(
                first: firstLoad, warm: warmLoaded ? warmLoad : nil, addedBytes: addedBytes,
                cpu: loadCPU),
            timeline: MemoryTimeline(samples: samples, peak: peak),
            leak: LeakCheck(
                footprints: footprintsAfterEach, allowanceBytes: configuration.leakAllowanceBytes),
            utterances: utterances,
            disk: disk,
            cpu: cpuCost(since: runStartedCPU, over: runStarted.duration(to: clock.now))
        )
    }
}
