public import UttrflowCore
private import Foundation

/// The Mac a set of numbers came from.
///
/// Carried in the report rather than typed into the document afterwards. Performance
/// figures without the machine are not a measurement, and the one detail everybody
/// forgets to copy across is the one that explains the disagreement.
public struct MachineDescription: Sendable, Equatable {
    public let chip: String
    public let memoryBytes: Int64
    public let operatingSystem: String

    public init(chip: String, memoryBytes: Int64, operatingSystem: String) {
        self.chip = chip
        self.memoryBytes = memoryBytes
        self.operatingSystem = operatingSystem
    }

    public static func current() -> MachineDescription {
        MachineDescription(
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            memoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            operatingSystem: "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    /// Reads one `sysctl` string, or `nil` when this kernel does not publish it.
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(decoding: value.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Resident memory through one run of the app's life, plus the highest figure seen
/// while nobody was looking.
///
/// The samples are moments the profile chose; the peak is what polling caught between
/// them. Both are needed: a spike that has settled by the next sample is still a spike a
/// user's Mac had to find room for.
public struct MemoryTimeline: Sendable, Equatable {
    public let samples: [MemorySample]
    /// The highest figures seen while a dictation was in flight, or `nil` when nothing
    /// was watched.
    public let peak: MemoryReading?

    public init(samples: [MemorySample], peak: MemoryReading?) {
        self.samples = samples
        self.peak = peak
    }

    /// What each moment added to the footprint over the one before it, so a table can
    /// show the cost of a step rather than leaving the reader to subtract. `nil` for the
    /// first moment, which is the baseline and not a change.
    public var increments: [Int64?] {
        guard !samples.isEmpty else { return [] }
        let footprints = samples.map(\.reading.footprintBytes)
        return [nil] + zip(footprints, footprints.dropFirst()).map { $1 - $0 }
    }
}

/// What loading the speech model costs the first time against every time after.
///
/// The user meets the first one. Reporting only the warm figure would describe a wait
/// nobody has ever had.
public struct ModelLoadProfile: Sendable, Equatable {
    /// The first load in this process.
    public let first: Duration
    /// A second, independent load in the same process, or `nil` when it was not
    /// attempted.
    public let warm: Duration?
    /// What the loaded model added to the process footprint.
    public let addedBytes: Int64?
    /// What the first load cost in processor time.
    ///
    /// Separate from the seconds it took, and the gap between them is the finding: a load
    /// that takes four seconds holding several cores busy is a very different thing to one
    /// that takes four seconds waiting on a disk, and only this says which.
    public let cpu: CPUCost?

    public init(first: Duration, warm: Duration?, addedBytes: Int64?, cpu: CPUCost? = nil) {
        self.first = first
        self.warm = warm
        self.addedBytes = addedBytes
        self.cpu = cpu
    }

    /// How much of the first load the second one avoided, `0...1`, or `nil` when there
    /// was no second load.
    public var savedByWarming: Double? {
        guard let warm, first.inSeconds > 0 else { return nil }
        return max(0, 1 - warm.inSeconds / first.inSeconds)
    }
}

/// What a working install occupies.
public struct DiskFootprint: Sendable, Equatable {
    /// The downloaded speech model, measured on disk rather than taken from the
    /// catalogue: what a repository says it ships and what lands in the folder are two
    /// different numbers, and the second is the one a user's disk sees.
    public let speechModelBytes: Int64
    /// The signed application bundle, when one has been built to measure.
    public let applicationBytes: Int64?

    public init(speechModelBytes: Int64, applicationBytes: Int64?) {
        self.speechModelBytes = speechModelBytes
        self.applicationBytes = applicationBytes
    }

    public var totalBytes: Int64 { speechModelBytes + (applicationBytes ?? 0) }
}

/// Everything one profiling run established.
public struct PerformanceReport: Sendable, Equatable {
    public let machine: MachineDescription
    public let modelLoad: ModelLoadProfile
    public let timeline: MemoryTimeline
    public let leak: LeakCheck
    public let utterances: [UtteranceProfile]
    public let disk: DiskFootprint
    /// What the whole run cost the processor, first reading to last.
    ///
    /// Includes the profile's own overhead — reading memory every 20 ms, synthesising
    /// nothing, printing nothing — which is why the per-length figures below are the ones
    /// to quote and this is context for them.
    public let cpu: CPUCost?

    public init(
        machine: MachineDescription,
        modelLoad: ModelLoadProfile,
        timeline: MemoryTimeline,
        leak: LeakCheck,
        utterances: [UtteranceProfile],
        disk: DiskFootprint,
        cpu: CPUCost? = nil
    ) {
        self.machine = machine
        self.modelLoad = modelLoad
        self.timeline = timeline
        self.leak = leak
        self.utterances = utterances
        self.disk = disk
        self.cpu = cpu
    }

    /// How the whole journey grows with utterance length.
    public var scaling: ScalingAnalysis { ScalingAnalysis(utterances) }

    /// How one stage grows with utterance length.
    public func scaling(of stage: PipelineStage) -> ScalingAnalysis {
        ScalingAnalysis(utterances, stage: stage)
    }

    /// Stages something timed, in the order the journey runs.
    ///
    /// Derived from ``PipelineStage/allCases`` rather than listed, so a stage added to
    /// the pipeline appears in the report the day something times it.
    public var timedStages: [PipelineStage] {
        PipelineStage.allCases.filter { stage in
            utterances.contains { $0.stages.contains { $0.stage == stage } }
        }
    }

    /// The largest footprint the process ever reached, whether it was a named moment or
    /// caught between them.
    public var peakFootprintBytes: Int64? {
        ([timeline.peak?.footprintBytes] + timeline.samples.map { $0.reading.footprintBytes })
            .compactMap(\.self).max()
    }
}
