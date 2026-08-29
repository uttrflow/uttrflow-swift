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
    /// Stages nothing timed. Named rather than shown as zero, because the profile reads
    /// audio off disk and never captures, and a zero would read as "instant".
    public let unmeasuredStages: [PipelineStage]
    /// What the timed runs of this length cost in processor time, summed over all of
    /// them. `nil` when the processor could not be read.
    ///
    /// Summed rather than averaged, and then divided by ``runs`` where a per-dictation
    /// figure is wanted. The sum is what was actually observed; an average of an average
    /// is where a run that failed quietly stops showing up.
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

    /// Processor seconds one dictation of this length costs.
    ///
    /// The figure that answers "what will this do to a battery", and the one that
    /// transfers to a Mac nobody measured: a slower chip does the same work, so this
    /// number moves far less across machines than the wall-clock seconds beside it.
    public var cpuSecondsPerDictation: Double? {
        guard let cpu, runs > 0 else { return nil }
        return cpu.cpuSeconds / Double(runs)
    }

    /// Processor seconds spent per second of speech.
    public var cpuSecondsPerAudioSecond: Double? {
        guard let each = cpuSecondsPerDictation, audioSeconds > 0 else { return nil }
        return each / audioSeconds
    }

    /// Wall-clock seconds spent per second of speech.
    ///
    /// Includes the fixed cost of starting a dictation, so a three-second utterance
    /// looks dear here and a one-minute one cheap. That is the honest shape of it, and
    /// ``ScalingAnalysis`` is where the fixed cost is separated out.
    public var costPerAudioSecond: Double {
        audioSeconds > 0 ? endToEnd.typical.inSeconds / audioSeconds : 0
    }

    /// How many times faster than real time the whole journey ran.
    public var realTimeFactor: Double {
        endToEnd.typical.inSeconds > 0 ? audioSeconds / endToEnd.typical.inSeconds : 0
    }

    /// The typical seconds spent, for one stage or for the whole journey.
    ///
    /// - Parameter stage: `nil` for end to end.
    /// - Returns: `nil` for a stage nothing timed, so a scaling verdict is never drawn
    ///   through a point that does not exist.
    public func wallSeconds(of stage: PipelineStage?) -> Double? {
        guard let stage else { return endToEnd.typical.inSeconds }
        return stages.first { $0.stage == stage }?.typical.inSeconds
    }
}

/// Whether cost grows with utterance length, faster than length, or slower.
///
/// The question the profile exists to answer: if transcription is super-linear, a
/// two-minute dictation behaves nothing like the fifteen-second test that was used to
/// sign it off, and nobody finds out until a user does.
public struct ScalingAnalysis: Sendable, Equatable {
    /// What the step from one length to the next cost.
    ///
    /// Marginal rather than average, so the fixed per-dictation overhead — model
    /// warm-up, prompt assembly — is charged once to the shortest utterance and never
    /// again. An average would hide a genuine bend behind that overhead shrinking.
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

    /// How far the marginal cost may move before the difference is called a trend.
    ///
    /// A quarter, which is wide. Three lengths timed a handful of times each on a laptop
    /// that is also running everything else cannot support a tighter claim, and a
    /// profile that cried super-linear at every thermal wobble would be ignored.
    public static let tolerance = 0.25

    public let steps: [Step]
    public let verdict: Verdict

    public init(steps: [Step], verdict: Verdict) {
        self.steps = steps
        self.verdict = verdict
    }

    /// Reads the shape off the profiles.
    ///
    /// - Parameters:
    ///   - profiles: One per length, in any order.
    ///   - stage: Which stage to read, or `nil` for the whole journey. Per stage as well
    ///     as overall because they need not agree: a recogniser that works in fixed
    ///     windows can bend while the clean-up pass beside it stays straight, and only
    ///     the stage-level answer says which one to go and look at.
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
