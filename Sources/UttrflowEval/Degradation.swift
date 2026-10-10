// Deterministic degraded variants of one clip, for measuring accuracy away from a quiet room.
private import Foundation

/// A sound added under speech; see `Docs/eval-methodology.md#accuracy-in-noise-noise`.
public enum NoiseKind: String, CaseIterable, Sendable {
    /// Flat-spectrum hiss.
    case white
    /// Hiss falling 3 dB per octave, closer to a fan or air conditioning than white noise.
    case pink
    /// Mains hum: 100 Hz and its harmonics up to 500 Hz.
    case hum
    /// Several synthetic voices talking at once, none of them intelligible.
    case babble
    /// Synthetic tonal music: a chord that changes every half second.
    case music

    /// Synthetic voices summed into babble.
    static let babbleVoices = 6

    /// `count` samples of this sound at `sampleRate`, the same for the same `seed`, at no particular level.
    public func samples(count: Int, sampleRate: Int, seed: UInt64) -> [Float] {
        var random = SeededNoise(seed: seed)
        let rate = Double(sampleRate)
        switch self {
        case .white:
            return random.white(count)
        case .pink:
            return Self.pinked(random.white(count))
        case .hum:
            let phases = (1...5).map { _ in Double(random.next()) * .pi }
            return (0..<count).map { index in
                let time = Double(index) / rate
                return Float(
                    phases.enumerated().reduce(0.0) { sum, harmonic in
                        let order = Double(harmonic.offset + 1)
                        return sum + sin(2 * .pi * 100 * order * time + harmonic.element) / order
                    })
            }
        case .babble:
            var mixed = [Float](repeating: 0, count: count)
            for _ in 0..<Self.babbleVoices {
                for (index, sample) in Self.voice(count: count, rate: rate, random: &random).enumerated() {
                    mixed[index] += sample
                }
            }
            return mixed
        case .music:
            return NonSpeechSound.chords(count: count, rms: -20, sampleRate: sampleRate)
        }
    }

    /// White noise filtered to fall 3 dB per octave (Paul Kellet's economy filter).
    static func pinked(_ white: [Float]) -> [Float] {
        var (b0, b1, b2): (Float, Float, Float) = (0, 0, 0)
        return white.map { sample in
            b0 = 0.99765 * b0 + sample * 0.099_046_0
            b1 = 0.96300 * b1 + sample * 0.296_516_4
            b2 = 0.57000 * b2 + sample * 1.052_691_3
            return b0 + b1 + b2 + sample * 0.1848
        }
    }

    /// One synthetic talker: a buzzy harmonic tone whose pitch drifts, switched on and off at a syllable rate.
    static func voice(count: Int, rate: Double, random: inout SeededNoise) -> [Float] {
        let basePitch = 110 + 70 * Double(random.next() + 1)
        let syllableRate = 3.5 + Double(random.next() + 1)
        let offset = Double(random.next() + 1) * .pi
        var phase = 0.0
        return (0..<count).map { index in
            let time = Double(index) / rate
            let pitch = basePitch * (1 + 0.1 * sin(2 * .pi * 0.7 * time + offset))
            phase += 2 * .pi * pitch / rate
            let envelope = max(0, sin(2 * .pi * syllableRate * time + offset))
            let tone = (1...12).reduce(0.0) { $0 + sin(Double($1) * phase) / Double($1) }
            return Float(envelope * tone)
        }
    }
}

/// One condition a clip is replayed under; the reference every other is compared with is ``clean``.
public enum Degradation: Sendable, Equatable, CustomStringConvertible {
    /// The clip as recorded.
    case clean
    /// The clip with `kind` added so speech power sits `snr` dB above the noise's.
    case noise(NoiseKind, snr: Double)

    /// The signal-to-noise ratios each noise is added at, from mild to as loud as the speech.
    public static let snrSteps: [Double] = [20, 10, 5, 0]

    /// Every condition the noise sweep replays a passage under, clean first.
    public static let noiseSweep: [Degradation] =
        [.clean] + NoiseKind.allCases.flatMap { kind in snrSteps.map { .noise(kind, snr: $0) } }

    public var description: String {
        switch self {
        case .clean: "clean"
        case .noise(let kind, let snr): "\(kind.rawValue) \(Int(snr)) dB"
        }
    }

    /// `samples` under this condition, the same for the same `seed`; a mix past full scale is scaled down whole.
    public func applied(to samples: [Float], sampleRate: Int, seed: UInt64) -> [Float] {
        switch self {
        case .clean:
            return samples
        case .noise(let kind, let snr):
            let speech = NonSpeechSound.rmsDecibels(of: samples)
            guard speech.isFinite else { return samples }
            let noise = NonSpeechSound.scaled(
                kind.samples(count: samples.count, sampleRate: sampleRate, seed: seed),
                toRMSDecibels: speech - snr)
            let mixed = zip(samples, noise).map(+)
            let peak = mixed.reduce(Float(0)) { max($0, abs($1)) }
            return peak > 1 ? mixed.map { $0 / peak } : mixed
        }
    }

    /// The seed for one recording, from the run's seed and the recording's identifier alone.
    public static func seed(for recordingID: String, run: UInt64) -> UInt64 {
        // FNV-1a, because Swift's own hashing is salted per process.
        recordingID.utf8.reduce(0xCBF2_9CE4_8422_2325 ^ run) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}

/// Where each noise starts to cost words: the mildest step whose word error rate passes clean by a margin.
public enum NoiseBreakpoint {
    /// How far above the clean word error rate counts as falling off, in rate (5 percentage points).
    public static let margin = 0.05

    /// Per noise in `rows`, the first of `Degradation.snrSteps` past `clean` by over `margin`; `nil` if none.
    public static func first(
        in rows: [ConditionTable<Degradation>.Row], clean: Double
    ) -> [(kind: NoiseKind, snr: Double?)] {
        NoiseKind.allCases.compactMap { kind in
            let steps = Degradation.snrSteps.compactMap { snr in
                rows.first { $0.condition == .noise(kind, snr: snr) }
            }
            guard !steps.isEmpty else { return nil }
            let fallen = steps.first { $0.wordErrorRate - clean > margin }
            guard case .noise(_, let snr)? = fallen?.condition else { return (kind, nil) }
            return (kind, snr)
        }
    }
}
