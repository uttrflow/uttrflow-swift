// Deterministic tempo and pitch variants of one clip, for measuring the pace-dependent thresholds.
private import Foundation

/// Changes the speaking rate of a clip without changing its pitch (waveform-similarity overlap-add).
public enum TimeStretch {
    /// Analysis window length in seconds.
    static let windowSeconds = 0.04
    /// How far either way the next window may move to line up with the last, in seconds.
    static let searchSeconds = 0.015

    /// `samples` played `rate` times as fast with the pitch kept; the result holds `samples.count / rate` samples.
    public static func stretched(_ samples: [Float], sampleRate: Int, rate: Double) -> [Float] {
        guard rate > 0, rate.isFinite, sampleRate > 0, !samples.isEmpty, rate != 1 else { return samples }
        let window = max(8, (Int(windowSeconds * Double(sampleRate)) / 2) * 2)
        let hop = window / 2
        let search = max(1, Int(searchSeconds * Double(sampleRate)))
        let outputCount = max(1, Int((Double(samples.count) / rate).rounded()))
        guard samples.count > window + 2 * search else {
            return resampled(samples, count: outputCount)
        }
        let fade = (0..<window).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(window))) }
        var output = [Float](repeating: 0, count: outputCount + window)
        var weight = [Float](repeating: 0, count: outputCount + window)
        var previous = 0
        var frame = 0
        while frame * hop < outputCount {
            let nominal = Int((Double(frame * hop) * rate).rounded())
            var chosen = min(max(nominal, 0), samples.count - window)
            if frame > 0 {
                chosen = bestAlignment(
                    in: samples, near: nominal, target: previous + hop, window: window, search: search)
            }
            let base = frame * hop
            for index in 0..<window {
                output[base + index] += samples[chosen + index] * fade[index]
                weight[base + index] += fade[index]
            }
            previous = chosen
            frame += 1
        }
        return (0..<outputCount).map { index in
            weight[index] > 1e-3 ? output[index] / weight[index] : output[index]
        }
    }

    /// The start near `nominal` whose window best continues the audio that followed the last chosen start.
    private static func bestAlignment(
        in samples: [Float], near nominal: Int, target: Int, window: Int, search: Int
    ) -> Int {
        let highest = samples.count - window
        let lowest = max(0, nominal - search)
        let upper = min(highest, nominal + search)
        guard lowest <= upper, target >= 0, target <= highest else { return min(max(nominal, 0), highest) }
        var best = min(max(nominal, lowest), upper)
        var bestScore = -Float.infinity
        // Every fourth sample of every second start is enough to line two waveforms up.
        samples.withUnsafeBufferPointer { buffer in
            for start in stride(from: lowest, through: upper, by: 2) {
                var dot: Float = 0
                var energy: Float = 0
                for index in stride(from: 0, to: window, by: 4) {
                    let candidate = buffer[start + index]
                    dot += candidate * buffer[target + index]
                    energy += candidate * candidate
                }
                let score = dot / (energy.squareRoot() + 1e-9)
                if score > bestScore {
                    bestScore = score
                    best = start
                }
            }
        }
        return best
    }

    /// `samples` read at a steady step into `count` samples, linearly interpolated.
    static func resampled(_ samples: [Float], count: Int) -> [Float] {
        guard count > 0, samples.count > 1 else { return Array(repeating: samples.first ?? 0, count: count) }
        let step = Double(samples.count - 1) / Double(max(1, count - 1))
        return (0..<count).map { index in
            let position = Double(index) * step
            let low = min(Int(position), samples.count - 2)
            let fraction = Float(position - Double(low))
            return samples[low] * (1 - fraction) + samples[low + 1] * fraction
        }
    }
}

/// Changes the pitch of a clip without changing its length.
public enum PitchShift {
    /// `samples` with every pitch moved by `semitones` and the length kept (stretch, then resample).
    public static func shifted(_ samples: [Float], sampleRate: Int, semitones: Double) -> [Float] {
        guard semitones != 0, semitones.isFinite, !samples.isEmpty else { return samples }
        let ratio = pow(2, semitones / 12)
        let slowed = TimeStretch.stretched(samples, sampleRate: sampleRate, rate: 1 / ratio)
        return TimeStretch.resampled(slowed, count: samples.count)
    }
}

/// One tempo or pitch condition a clip is replayed under; the reference every other is compared with is ``original``.
public enum SpeechVariant: Sendable, Equatable, CustomStringConvertible {
    /// The clip as recorded.
    case original
    /// The clip spoken `factor` times as fast, pitch kept.
    case rate(Double)
    /// The clip with its pitch moved by `semitones`, tempo kept.
    case pitch(Double)

    /// The speaking-rate factors of the sweep; 1.0 is the reference.
    public static let rateFactors: [Double] = [0.7, 0.85, 1.3, 1.6, 1.9]
    /// The pitch shifts of the sweep, in semitones.
    public static let pitchSemitones: [Double] = [-4, -2, 2, 4, 6]

    /// Every condition the sweep replays a passage under, the original first.
    public static let sweep: [SpeechVariant] =
        [.original] + rateFactors.map { .rate($0) } + pitchSemitones.map { .pitch($0) }

    public var description: String {
        switch self {
        case .original: "1.0x"
        case .rate(let factor): String(format: "%.2fx", factor).replacingOccurrences(of: "0x", with: "x")
        case .pitch(let semitones): String(format: "%+.0f st", semitones)
        }
    }

    /// `samples` under this condition; the same samples always give the same result.
    public func applied(to samples: [Float], sampleRate: Int) -> [Float] {
        switch self {
        case .original: samples
        case .rate(let factor): TimeStretch.stretched(samples, sampleRate: sampleRate, rate: factor)
        case .pitch(let semitones): PitchShift.shifted(samples, sampleRate: sampleRate, semitones: semitones)
        }
    }
}
