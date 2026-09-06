// What one utterance length costs, and whether cost scales with length.
public import UttrflowCore

/// What one utterance length costs, end to end and stage by stage.
public struct UtteranceProfile: Sendable, Equatable {
    public let length: ProfilePassage.Length
    /// Seconds of speech actually in the recording, not the length's nominal target.
    public let audioSeconds: Double
    /// The whole journey, timed as one span so anything between the stages is counted.
    public let endToEnd: DurationSummary
    /// Each stage that something timed, in the order the journey runs.
    public let stages: [StageLatency]
    /// Stages nothing timed, named rather than shown as zero; the profile reads audio off disk.
    public let unmeasuredStages: [PipelineStage]
    /// Processor cost summed over every timed run of this length; `nil` when the processor is unreadable.
    public let cpu: CPUCost?
    /// How many timed runs ``cpu`` covers.
    public let runs: Int

    public init(
        length: ProfilePassage.Length,
        audioSeconds: Double,
        endToEnd: DurationSummary,
        stages: [StageLatency],
        unmeasuredStages: [PipelineStage],
        cpu: CPUCost? = nil,
        runs: Int = 0
    ) {
        self.length = length
        self.audioSeconds = audioSeconds
        self.endToEnd = endToEnd
        self.stages = stages
        self.unmeasuredStages = unmeasuredStages
        self.cpu = cpu
        self.runs = runs
    }

    /// Processor seconds one dictation of this length costs, the figure that transfers across Macs.
    public var cpuSecondsPerDictation: Double? {
        guard let cpu, runs > 0 else { return nil }
        return cpu.cpuSeconds / Double(runs)
    }

    /// Processor seconds spent per second of speech.
    public var cpuSecondsPerAudioSecond: Double? {
        guard let each = cpuSecondsPerDictation, audioSeconds > 0 else { return nil }
        return each / audioSeconds
    }

    /// Wall-clock seconds per second of speech, start-up cost included; ``ScalingAnalysis`` separates it.
    public var costPerAudioSecond: Double {
        audioSeconds > 0 ? endToEnd.typical.inSeconds / audioSeconds : 0
    }

    /// How many times faster than real time the whole journey ran.
    public var realTimeFactor: Double {
        endToEnd.typical.inSeconds > 0 ? audioSeconds / endToEnd.typical.inSeconds : 0
    }

    /// Typical seconds for one stage, or end to end for `nil`; `nil` for a stage nothing timed.
    public func wallSeconds(of stage: PipelineStage?) -> Double? {
        guard let stage else { return endToEnd.typical.inSeconds }
        return stages.first { $0.stage == stage }?.typical.inSeconds
    }
}

/// Whether cost grows with utterance length, faster than length, or slower.
public struct ScalingAnalysis: Sendable, Equatable {
    /// The marginal cost of the step from one length to the next, so fixed overhead is charged once.
    public struct Step: Sendable, Equatable {
        public let from: ProfilePassage.Length
        public let to: ProfilePassage.Length
        public let extraAudioSeconds: Double
        public let extraWallSeconds: Double

        public init(
            from: ProfilePassage.Length, to: ProfilePassage.Length,
            extraAudioSeconds: Double, extraWallSeconds: Double
        ) {
            self.from = from
            self.to = to
            self.extraAudioSeconds = extraAudioSeconds
            self.extraWallSeconds = extraWallSeconds
        }

        /// Extra wall-clock seconds bought by one extra second of speech.
        public var marginalCost: Double {
            extraAudioSeconds > 0 ? extraWallSeconds / extraAudioSeconds : 0
        }
    }

    public enum Verdict: String, Sendable, Equatable, CaseIterable {
        /// Fewer than two steps, so there is nothing to compare.
        case undetermined
        /// Later seconds of speech cost less than earlier ones.
        case subLinear
        /// Every second of speech costs about the same.
        case linear
        /// Later seconds cost more. The finding that invalidates short-utterance testing.
        case superLinear
    }

    /// How far the marginal cost may move before it is called a trend; wide, since runs are few and noisy.
    public static let tolerance = 0.25

    public let steps: [Step]
    public let verdict: Verdict

    public init(steps: [Step], verdict: Verdict) {
        self.steps = steps
        self.verdict = verdict
    }

    /// Reads the shape off the profiles, per `stage` or end to end, since stages need not agree.
    public init(_ profiles: [UtteranceProfile], stage: PipelineStage? = nil) {
        let points: [(length: ProfilePassage.Length, audio: Double, wall: Double)] =
            profiles.compactMap { profile in
                guard let wall = profile.wallSeconds(of: stage) else { return nil }
                return (profile.length, profile.audioSeconds, wall)
            }
            .sorted { $0.audio < $1.audio }

        let steps = zip(points, points.dropFirst()).map { shorter, longer in
            Step(
                from: shorter.length, to: longer.length,
                extraAudioSeconds: longer.audio - shorter.audio,
                extraWallSeconds: longer.wall - shorter.wall
            )
        }

        guard let first = steps.first, let last = steps.last, steps.count >= 2, first.marginalCost > 0
        else {
            self.init(steps: steps, verdict: .undetermined)
            return
        }

        let ratio = last.marginalCost / first.marginalCost
        let verdict: Verdict =
            switch ratio {
            case ..<(1 - Self.tolerance): .subLinear
            case (1 + Self.tolerance)...: .superLinear
            default: .linear
            }
        self.init(steps: steps, verdict: verdict)
    }
}
