// The value types a performance profile reports.
public import UttrflowCore
private import Foundation

/// The Mac a set of numbers came from, carried in the report rather than typed in afterwards.
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

/// Resident memory at chosen moments of one run, plus the highest figure polling caught between them.
public struct MemoryTimeline: Sendable, Equatable {
    public let samples: [MemorySample]
    /// The highest figures seen while a dictation was in flight, or `nil` when nothing was watched.
    public let peak: MemoryReading?

    public init(samples: [MemorySample], peak: MemoryReading?) {
        self.samples = samples
        self.peak = peak
    }

    /// What each moment adds over the one before; `nil` for the first, which is the baseline.
    public var increments: [Int64?] {
        guard !samples.isEmpty else { return [] }
        let footprints = samples.map(\.reading.footprintBytes)
        return [nil] + zip(footprints, footprints.dropFirst()).map { $1 - $0 }
    }
}

/// What loading the speech model costs the first time against every time after.
public struct ModelLoadProfile: Sendable, Equatable {
    /// The first load in this process.
    public let first: Duration
    /// A second, independent load in the same process, or `nil` when none is attempted.
    public let warm: Duration?
    /// What the loaded model added to the process footprint.
    public let addedBytes: Int64?
    /// Processor time of the first load, which says whether four seconds is cores busy or a disk waited on.
    public let cpu: CPUCost?

    public init(first: Duration, warm: Duration?, addedBytes: Int64?, cpu: CPUCost? = nil) {
        self.first = first
        self.warm = warm
        self.addedBytes = addedBytes
        self.cpu = cpu
    }

    /// How much of the first load the second avoids, `0...1`, or `nil` without a second load.
    public var savedByWarming: Double? {
        guard let warm, first.inSeconds > 0 else { return nil }
        return max(0, 1 - warm.inSeconds / first.inSeconds)
    }
}

/// What a working install occupies.
public struct DiskFootprint: Sendable, Equatable {
    /// The speech model's size measured on disk, which is what a user's disk sees, not the catalogue's.
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
    /// What the whole run cost the processor, including the profile's own polling overhead.
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

    /// Stages something timed, in pipeline order, derived from ``PipelineStage/allCases``.
    public var timedStages: [PipelineStage] {
        PipelineStage.allCases.filter { stage in
            utterances.contains { $0.stages.contains { $0.stage == stage } }
        }
    }

    /// The largest footprint the process reaches, whether at a named moment or between them.
    public var peakFootprintBytes: Int64? {
        ([timeline.peak?.footprintBytes] + timeline.samples.map { $0.reading.footprintBytes })
            .compactMap(\.self).max()
    }
}
