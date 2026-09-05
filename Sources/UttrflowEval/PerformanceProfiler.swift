public import UttrflowCore

/// Drives one machine through the app's life and records what it costs, knowing nothing of the engines.
public struct PerformanceProfiler: Sendable {
    /// How hard to push, and where the profile draws its lines.
    public struct Configuration: Sendable, Equatable {
        /// How many times each length is timed; small, since the figure wanted is a median of real runs.
        public var repetitions: Int
        /// How many consecutive dictations the leak check watches.
        public var leakRepetitions: Int
        /// Which length the leak check repeats: a paragraph, which is what a person dictates over and over.
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

    /// What the profiler is doing, so an unattended run says something while a minute of speech decodes.
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

    /// Runs the whole profile; `loadSpeechModel` runs twice and must load fresh, `dictate` never throws.
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

        // A profile of a recogniser that did not load would be a page of zeroes posing as a result.
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

        // Thrown away: the first dictation pays for buffers every later one reuses.
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
                    // Only runs whose processor cost was read, so a partial sum is not split by a full count.
                    cpu: CPUCost.total(of: costs),
                    runs: costs.count
                ))
        }
        sample("after the length sweep")

        // Last, so a second recogniser never sits beside the first while the rows above are measured.
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
