// Models the audio a held key keeps when it comes up before the last word has finished.
private import Foundation
private import UttrflowCore

/// What the stop path keeps of a clip released `offset` before its speech ends, for one tap size and phase.
public enum TailCut {
    /// The width of one loudness frame, in canonical samples (10 ms).
    static let frameSamples = AudioSamples.canonicalSampleRate / 100

    /// Speech is a frame whose level is within this many decibels of the clip's loudest frame.
    public static let speechFloorDecibels: Float = 40

    /// From the first frame loud enough to be speech to just after the last, or nil when none is.
    public static func speechRange(of samples: [Float]) -> Range<Int>? {
        let levels = stride(from: 0, to: samples.count, by: frameSamples).map { start in
            let frame = samples[start..<min(samples.count, start + frameSamples)]
            return (frame.reduce(Float(0)) { $0 + $1 * $1 } / Float(frame.count)).squareRoot()
        }
        guard let peak = levels.max(), peak > 0 else { return nil }
        let floor = peak * Float(pow(10, Double(-speechFloorDecibels / 20)))
        guard let first = levels.firstIndex(where: { $0 >= floor }),
            let last = levels.lastIndex(where: { $0 >= floor })
        else { return nil }
        return (first * frameSamples)..<min(samples.count, (last + 1) * frameSamples)
    }

    /// The sample just after the last frame loud enough to be speech, or zero when nothing is.
    public static func speechEnd(of samples: [Float]) -> Int {
        speechRange(of: samples)?.upperBound ?? 0
    }

    /// One tap period in canonical samples, for a tap of `tapFrames` at the device's `inputRate`.
    public static func tapSamples(tapFrames: Int, inputRate: Double) -> Int {
        guard tapFrames > 0, inputRate > 0 else { return 0 }
        return Int((Double(tapFrames) * Double(AudioSamples.canonicalSampleRate) / inputRate).rounded())
    }

    /// The samples the drained stop hands over: up to the end of the block that was filling at `cut`.
    public static func kept(_ samples: [Float], cut: Int, tapSamples: Int, phase: Int) -> [Float] {
        let cut = max(0, min(samples.count, cut))
        guard tapSamples > 0 else { return Array(samples[..<cut]) }
        let into = ((cut - phase) % tapSamples + tapSamples) % tapSamples
        let end = into == 0 ? cut : cut + tapSamples - into
        return Array(samples[..<min(samples.count, end)])
    }

    /// Whether the transcript still ends on the reference's last word, judged by the word alignment.
    public static func keptLastWord(reference: [String], hypothesis: [String]) -> Bool {
        guard !reference.isEmpty else { return true }
        let alignment = WordErrorRate.measure(reference: reference, hypothesis: hypothesis).alignment
        let last = alignment.last { $0.kind != .insertion }
        return last?.kind == .match
    }
}
