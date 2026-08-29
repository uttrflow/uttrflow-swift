/// Whether repeated dictations leave memory behind.
///
/// The single most valuable thing a profile can find. One dictation's footprint says
/// nothing — a model allocates scratch space, an allocator holds pages back — but a
/// figure that climbs at every repetition and never comes down is a defect that ends
/// with a swapping Mac after an afternoon's work.
///
/// The readings must all be taken after the *same* point in the cycle, and never
/// including the first dictation of the process: that one pays for lazily created
/// buffers the rest reuse, and counting it turns warm-up into a leak.
public struct LeakCheck: Sendable, Equatable {
    /// What the readings support saying.
    ///
    /// Four outcomes rather than pass/fail because they lead to different work: growth
    /// that wobbles needs a longer run, growth that climbs every time needs a fix, and
    /// two readings need neither because they cannot show a trend at all.
    public enum Verdict: String, Sendable, Equatable, CaseIterable {
        /// Fewer than three readings. Two points are a line whatever they are.
        case undetermined
        /// Growth stayed inside the allowance.
        case clean
        /// Grew past the allowance, but fell back at least once on the way. Real, or a
        /// long-lived cache settling — a longer run is the only way to tell.
        case suspect
        /// Grew past the allowance and never once fell back.
        case leaking
    }

    /// How much total growth is treated as settling rather than leaking.
    ///
    /// Over the default ten dictations this is a little over 3 MB each, which for
    /// someone dictating a hundred times in a working day is roughly a third of a
    /// gigabyte. Anything looser would call that noise.
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

    /// Growth spread over the gaps between readings, which is the figure that
    /// extrapolates to a working day.
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

    /// Only ``Verdict/clean`` passes. ``Verdict/undetermined`` is not a pass — it is a
    /// run that was too short to have asked the question.
    public var passed: Bool { verdict == .clean }
}
