// Models a start cue leaking from the speaker into the head of a recording.
private import Foundation

/// Mixes a rendered cue into the head of a clip at a chosen peak level, the way the start cue lands in a capture.
public enum CueBleed {
    /// The largest absolute sample, in dBFS; minus infinity for silence.
    public static func peakDecibels(of samples: [Float]) -> Double {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        return peak > 0 ? 20 * log10(Double(peak)) : -.infinity
    }

    /// `cue` scaled so its peak sits at `peakDecibels` dBFS; silence stays silent.
    public static func scaled(_ cue: [Float], toPeakDecibels peakDecibels: Double) -> [Float] {
        let current = self.peakDecibels(of: cue)
        guard current.isFinite else { return cue }
        let gain = Float(pow(10, (peakDecibels - current) / 20))
        return cue.map { $0 * gain }
    }

    /// The capture: `lead` samples of silence then `speech`, with `cue` added from the first sample.
    public static func mixed(speech: [Float], lead: Int, cue: [Float]) -> [Float] {
        let lead = max(0, lead)
        var output = [Float](repeating: 0, count: max(lead + speech.count, cue.count))
        for (index, sample) in speech.enumerated() { output[lead + index] = sample }
        for (index, sample) in cue.enumerated() { output[index] += sample }
        return output
    }
}
