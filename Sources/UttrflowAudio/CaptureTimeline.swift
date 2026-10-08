// Checks each tap buffer against the hardware's sample clock, so a lost buffer is noticed instead of joining its neighbours.
internal import AVFoundation
private import Synchronization
internal import UttrflowCore

/// The hardware sample clock seen through the tap, so continuity is checked rather than assumed. See Docs/audio-capture.md.
struct CaptureTimeline: Sendable, Equatable {
    /// What a buffer's own timestamp says about the time before it.
    enum Step: Sendable, Equatable {
        case continuous
        /// Time passed that no buffer carried, short enough to stand in for with silence of that length.
        case silence(canonicalFrames: Int)
        /// Time passed that silence would misrepresent, so the recording is refused as one with a hole.
        case broken
    }

    /// The longest hole filled with silence; past it, a recording is refused as one the microphone left.
    static let longestFilledSeconds = 0.1

    let sampleRate: Double
    /// Where the next buffer should start, from the last one delivered; nil until one is.
    private var expected: Int64?
    /// Holes seen, filled or not, and their total length in hardware frames.
    private(set) var gaps = 0
    private(set) var gapFrames: Int64 = 0
    /// Buffers the tap could not hand on, which reappear as the hole before the next one.
    private(set) var droppedBuffers = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Total time no buffer carried, in milliseconds.
    var gapMilliseconds: Double { Self.milliseconds(gapFrames, at: sampleRate) }

    /// `frames` of hardware time at `sampleRate`, in milliseconds.
    static func milliseconds(_ frames: Int64, at sampleRate: Double) -> Double {
        sampleRate > 0 ? Double(frames) * 1000 / sampleRate : 0
    }

    /// Judges the time between the last delivered buffer and this one, which starts at `sampleTime`.
    mutating func arrived(at sampleTime: Int64?, frames: Int) -> Step {
        guard let sampleTime, let expected, sampleRate > 0 else { return .continuous }
        let hole = sampleTime - expected
        // Under half a buffer is the clock's own jitter, and a step back is a new clock, not lost time.
        guard hole * 2 > Int64(frames) else { return .continuous }
        gaps += 1
        gapFrames += hole
        guard Double(hole) <= sampleRate * Self.longestFilledSeconds else { return .broken }
        let canonical = Double(hole) * Double(AudioSamples.canonicalSampleRate) / sampleRate
        return .silence(canonicalFrames: Int(canonical.rounded()))
    }

    /// Records a buffer as handed on, so the next one is measured from its end.
    mutating func delivered(at sampleTime: Int64?, frames: Int) {
        expected = sampleTime.map { $0 + Int64(frames) }
    }

    /// Records a lost buffer, so the next one shows it as a hole from `sampleTime`, or from the last delivered when nil.
    mutating func dropped(resumingAt sampleTime: Int64? = nil) {
        droppedBuffers += 1
        if let sampleTime { expected = sampleTime }
    }
}

/// One engine's tap, holding its timeline on the audio thread and the zeros a short hole is filled with.
final class TapClock: @unchecked Sendable {
    /// Touched only from the tap callback, which never runs twice at once for one engine.
    private(set) var timeline: CaptureTimeline
    /// Preallocated, so filling a hole allocates nothing on the audio thread.
    private let zeros: [Float]
    /// Set on the audio thread and taken on the handoff's, so a refusal never takes a lock in the callback.
    private let broke = Atomic<Bool>(false)
    /// The timeline's counts, copied after each buffer so another thread reads them without touching the timeline.
    private let holes = Atomic<Int>(0)
    private let holeFrames = Atomic<Int64>(0)
    private let lost = Atomic<Int>(0)

    init(sampleRate: Double) {
        timeline = CaptureTimeline(sampleRate: sampleRate)
        let longest = Double(AudioSamples.canonicalSampleRate) * CaptureTimeline.longestFilledSeconds
        zeros = [Float](repeating: 0, count: Int(longest.rounded(.up)) + 1)
    }

    /// Converts one tap buffer into the handoff, preceded by silence for any short hole before it.
    func deliver(
        _ buffer: AVAudioPCMBuffer, at sampleTime: Int64?, through resampler: AudioResampler,
        into handoff: TapHandoff
    ) {
        let frames = Int(buffer.frameLength)
        var silence = 0
        switch timeline.arrived(at: sampleTime, frames: frames) {
        case .continuous: break
        case .silence(let canonicalFrames): silence = min(canonicalFrames, zeros.count)
        case .broken: broke.store(true, ordering: .releasing)
        }
        var converted = true
        let pushed = handoff.push { part in
            if silence > 0 {
                zeros.withUnsafeBufferPointer { part(UnsafeBufferPointer(rebasing: $0[..<silence])) }
            }
            do { try resampler.resample(buffer, into: part) } catch { converted = false }
        }
        if pushed, converted {
            timeline.delivered(at: sampleTime, frames: frames)
        } else {
            // Silence already handed on covers the hole before this buffer, so only this buffer is lost.
            timeline.dropped(resumingAt: pushed ? sampleTime : nil)
        }
        holes.store(timeline.gaps, ordering: .relaxed)
        holeFrames.store(timeline.gapFrames, ordering: .relaxed)
        lost.store(timeline.droppedBuffers, ordering: .relaxed)
    }

    /// What this engine's timeline has counted so far, safe to read from any thread.
    var gaps: CaptureGaps {
        CaptureGaps(
            holes: holes.load(ordering: .relaxed),
            milliseconds: CaptureTimeline.milliseconds(
                holeFrames.load(ordering: .relaxed), at: timeline.sampleRate),
            lostBuffers: lost.load(ordering: .relaxed))
    }

    /// Whether a hole too long to fill has been seen since the last call, clearing it.
    func takeBreak() -> Bool { broke.exchange(false, ordering: .acquiringAndReleasing) }
}
