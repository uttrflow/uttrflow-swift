/// Whether repeated dictations leave memory behind. See Docs/eval-profiling.md.
public struct LeakCheck: Sendable, Equatable {
    /// What the readings support saying; four outcomes because each leads to different work.
    public enum Verdict: String, Sendable, Equatable, CaseIterable {
        /// Fewer than three readings. Two points are a line whatever they are.
        case undetermined
        /// Growth stayed inside the allowance.
        case clean
        /// Grew past the allowance but fell back at least once; only a longer run tells a leak from a cache.
        case suspect
        /// Grew past the allowance and never once fell back.
        case leaking
    }

    /// Total growth treated as settling rather than leaking. See Docs/eval-profiling.md.
    public static let defaultAllowanceBytes: Int64 = 32 * 1024 * 1024

    /// Resident footprint after each dictation, in the order they ran.
    public let footprints: [Int64]
    public let allowanceBytes: Int64

    public init(footprints: [Int64], allowanceBytes: Int64 = defaultAllowanceBytes) {
        self.footprints = footprints
        self.allowanceBytes = allowanceBytes
    }

    /// End minus start. Negative when the process gave memory back, which happens.
    public var growthBytes: Int64 {
        guard let first = footprints.first, let last = footprints.last else { return 0 }
        return last - first
    }

    /// Growth per gap between readings, the figure that extrapolates to a working day.
    public var perDictationBytes: Int64 {
        guard footprints.count > 1 else { return 0 }
        return growthBytes / Int64(footprints.count - 1)
    }

    /// Whether the footprint never once fell between consecutive readings.
    public var neverFellBack: Bool {
        zip(footprints, footprints.dropFirst()).allSatisfy { $0 <= $1 }
    }

    public var verdict: Verdict {
        guard footprints.count >= 3 else { return .undetermined }
        guard growthBytes > allowanceBytes else { return .clean }
        return neverFellBack ? .leaking : .suspect
    }

    /// Only ``Verdict/clean`` passes; ``Verdict/undetermined`` is a run too short to have asked.
    public var passed: Bool { verdict == .clean }
}
