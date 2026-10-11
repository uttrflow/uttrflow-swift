// Deterministic room and channel effects: reverberation, band-limiting and mu-law telephone coding.
private import Foundation

/// The room and channel a clip passes through before the recogniser hears it.
enum ChannelEffects {
    /// A level-matched copy of `samples` in a room whose impulse response decays 60 dB over `rt60` seconds.
    static func reverberated(_ samples: [Float], rt60: Double, sampleRate: Int, seed: UInt64) -> [Float] {
        let dry = NonSpeechSound.rmsDecibels(of: samples)
        guard dry.isFinite, rt60 > 0 else { return samples }
        var random = SeededNoise(seed: seed)
        let length = max(1, Int(rt60 * Double(sampleRate)))
        let decay = log(1000.0) / Double(length)
        // The direct path at full strength, then a diffuse tail of decaying noise.
        let response = (0..<length).map { index in
            index == 0 ? 1.0 : Double(random.next()) * exp(-decay * Double(index)) * 0.5
        }
        let wet = convolved(samples.map(Double.init), response)
        let mixed = NonSpeechSound.scaled(wet.prefix(samples.count).map(Float.init), toRMSDecibels: dry)
        let peak = mixed.reduce(Float(0)) { max($0, abs($1)) }
        return peak > 1 ? mixed.map { $0 / peak } : mixed
    }

    /// `samples` with everything above `cutoff` hertz removed; unchanged when the cutoff is at or past Nyquist.
    static func bandLimited(_ samples: [Float], cutoff: Double, sampleRate: Int) -> [Float] {
        let rate = Double(sampleRate)
        guard cutoff > 0, cutoff < rate / 2, samples.count > 1 else { return samples }
        let half = 64
        let ratio = cutoff / rate
        let taps = (-half...half).map { offset -> Double in
            let x = Double(offset)
            let sinc = offset == 0 ? 2 * ratio : sin(2 * .pi * ratio * x) / (.pi * x)
            return sinc * (0.5 + 0.5 * cos(.pi * x / Double(half + 1)))
        }
        let gain = taps.reduce(0, +)
        return samples.indices.map { index in
            var sum = 0.0
            for (tap, weight) in taps.enumerated() {
                let source = index + tap - half
                if source >= 0, source < samples.count { sum += weight * Double(samples[source]) }
            }
            return Float(sum / gain)
        }
    }

    /// G.711 mu-law telephone coding: 3.4 kHz band, 8 kHz sampling, 8-bit companding, back at `sampleRate`.
    static func muLawCoded(_ samples: [Float], sampleRate: Int) -> [Float] {
        let line = 8_000.0
        let rate = Double(sampleRate)
        guard samples.count > 1, rate > line else { return samples.map { companded($0) } }
        let band = bandLimited(samples, cutoff: 3_400, sampleRate: sampleRate)
        let step = rate / line
        let coded = (0...Int(Double(band.count - 1) / step)).map {
            companded(interpolated(band, at: Double($0) * step))
        }
        return samples.indices.map { interpolated(coded, at: Double($0) / step) }
    }

    private static func interpolated(_ samples: [Float], at position: Double) -> Float {
        let lower = min(max(Int(position), 0), samples.count - 1)
        let upper = min(lower + 1, samples.count - 1)
        return samples[lower] + (samples[upper] - samples[lower]) * Float(position - Double(lower))
    }

    /// One sample through mu-law (mu 255) compression, 8-bit quantisation and expansion.
    private static func companded(_ value: Float) -> Float {
        let mu: Float = 255
        let clipped = min(max(value, -1), 1)
        let squeezed = (clipped < 0 ? -1 : 1) * log(1 + mu * abs(clipped)) / log(1 + mu)
        let restored = (squeezed * 127.5).rounded() / 127.5
        return (restored < 0 ? -1 : 1) * (pow(1 + mu, abs(restored)) - 1) / mu
    }

    /// Linear convolution through a radix-2 FFT, so a 1 s response over a long clip stays fast.
    private static func convolved(_ signal: [Double], _ response: [Double]) -> [Double] {
        let needed = signal.count + response.count - 1
        var size = 2
        while size < needed { size <<= 1 }
        var leftRe = signal + [Double](repeating: 0, count: size - signal.count)
        var leftIm = [Double](repeating: 0, count: size)
        var rightRe = response + [Double](repeating: 0, count: size - response.count)
        var rightIm = [Double](repeating: 0, count: size)
        transform(&leftRe, &leftIm, inverse: false)
        transform(&rightRe, &rightIm, inverse: false)
        for index in 0..<size {
            let real = leftRe[index] * rightRe[index] - leftIm[index] * rightIm[index]
            leftIm[index] = leftRe[index] * rightIm[index] + leftIm[index] * rightRe[index]
            leftRe[index] = real
        }
        transform(&leftRe, &leftIm, inverse: true)
        return Array(leftRe.prefix(needed))
    }

    /// In-place iterative radix-2 FFT over a power-of-two count; the inverse is scaled by 1/n.
    private static func transform(_ re: inout [Double], _ im: inout [Double], inverse: Bool) {
        let count = re.count
        var target = 0
        for index in 1..<count {
            var bit = count >> 1
            while target & bit != 0 {
                target ^= bit
                bit >>= 1
            }
            target |= bit
            if index < target {
                re.swapAt(index, target)
                im.swapAt(index, target)
            }
        }
        var length = 2
        while length <= count {
            let angle = (inverse ? 2 : -2) * Double.pi / Double(length)
            for start in stride(from: 0, to: count, by: length) {
                for offset in 0..<length / 2 {
                    let (low, high) = (start + offset, start + offset + length / 2)
                    let (cosine, sine) = (cos(angle * Double(offset)), sin(angle * Double(offset)))
                    let oddRe = re[high] * cosine - im[high] * sine
                    let oddIm = re[high] * sine + im[high] * cosine
                    re[high] = re[low] - oddRe
                    im[high] = im[low] - oddIm
                    re[low] += oddRe
                    im[low] += oddIm
                }
            }
            length <<= 1
        }
        if inverse {
            for index in 0..<count {
                re[index] /= Double(count)
                im[index] /= Double(count)
            }
        }
    }
}
