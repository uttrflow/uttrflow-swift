// How much time a recording lost between the microphone and the buffer, counted from the hardware clock.

/// Holes in one recording's capture timeline and the buffers lost into them. See Docs/audio-capture.md.
public struct CaptureGaps: Sendable, Equatable {
    /// No hole and no lost buffer, which is also what a source without a hardware clock reports.
    public static let none = CaptureGaps(holes: 0, milliseconds: 0, lostBuffers: 0)

    /// Holes seen, whether filled with silence or refused as a break.
    public let holes: Int
    /// Total length of those holes.
    public let milliseconds: Double
    /// Buffers the tap received but could not hand on, each of which shows up as part of a hole.
    public let lostBuffers: Int

    public init(holes: Int, milliseconds: Double, lostBuffers: Int) {
        self.holes = holes
        self.milliseconds = milliseconds
        self.lostBuffers = lostBuffers
    }

    /// Both counts together, for a recording that ran across more than one engine.
    public static func + (lhs: CaptureGaps, rhs: CaptureGaps) -> CaptureGaps {
        CaptureGaps(
            holes: lhs.holes + rhs.holes, milliseconds: lhs.milliseconds + rhs.milliseconds,
            lostBuffers: lhs.lostBuffers + rhs.lostBuffers)
    }
}
