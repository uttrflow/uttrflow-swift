// A confidence interval for a change in error rate, resampling the utterances both runs scored.
import Foundation

/// How a comparison decides whether a slice moved: a paired bootstrap over utterances. See Docs/eval-methodology.md.
package struct PairedBootstrap: Sendable, Equatable {
    /// The share of resampled changes the interval holds, split evenly between its two tails.
    let confidence: Double
    /// The chance of detecting a change as large as the reported minimum detectable change.
    let power: Double
    let resamples: Int
    /// Fixed, so the same two runs always produce the same interval and the same verdict.
    let seed: UInt64

    package init(
        confidence: Double = 0.95, power: Double = 0.8, resamples: Int = 2_000, seed: UInt64 = 0x5EED
    ) {
        self.confidence = confidence
        self.power = power
        self.resamples = resamples
        self.seed = seed
    }

    package static let standard = PairedBootstrap()

    /// One utterance scored in both runs.
    package struct Pair: Sendable, Equatable {
        let errorsBefore: Int
        let wordsBefore: Int
        let errorsAfter: Int
        let wordsAfter: Int

        package init(errorsBefore: Int, wordsBefore: Int, errorsAfter: Int, wordsAfter: Int) {
            self.errorsBefore = errorsBefore
            self.wordsBefore = wordsBefore
            self.errorsAfter = errorsAfter
            self.wordsAfter = wordsAfter
        }
    }

    /// The interval for a pooled-rate change, and the smallest change this sample can resolve.
    package struct Estimate: Sendable, Equatable {
        package let interval: ClosedRange<Double>
        /// The smallest true change the sample detects with the configured power, as a rate.
        package let minimumDetectableChange: Double
    }

    /// The estimate over these pairs; `nil` under two utterances, where there is no spread to resample.
    package func estimate(_ pairs: [Pair]) -> Estimate? {
        guard pairs.count >= 2, resamples > 0 else { return nil }
        var generator = SplitMix(state: seed)
        var deltas: [Double] = []
        deltas.reserveCapacity(resamples)
        for _ in 0..<resamples {
            var drawn = Pair(errorsBefore: 0, wordsBefore: 0, errorsAfter: 0, wordsAfter: 0)
            for _ in pairs.indices {
                let pick = pairs[Int(generator.next() % UInt64(pairs.count))]
                drawn = Pair(
                    errorsBefore: drawn.errorsBefore + pick.errorsBefore,
                    wordsBefore: drawn.wordsBefore + pick.wordsBefore,
                    errorsAfter: drawn.errorsAfter + pick.errorsAfter,
                    wordsAfter: drawn.wordsAfter + pick.wordsAfter)
            }
            guard drawn.wordsBefore > 0, drawn.wordsAfter > 0 else { continue }
            deltas.append(
                Double(drawn.errorsAfter) / Double(drawn.wordsAfter)
                    - Double(drawn.errorsBefore) / Double(drawn.wordsBefore))
        }
        guard !deltas.isEmpty else { return nil }
        deltas.sort()
        let tail = (1 - confidence) / 2
        let interval = Self.quantile(deltas, tail)...Self.quantile(deltas, 1 - tail)
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        let spread = (deltas.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(deltas.count)).squareRoot()
        let reach = Self.standardNormalQuantile(1 - tail) + Self.standardNormalQuantile(power)
        return Estimate(interval: interval, minimumDetectableChange: reach * spread)
    }

    /// The interval for one run's pooled rate: each utterance against an error-free copy of itself, so the change is the rate.
    func rateInterval(_ entries: [BaselineEntry]) -> ClosedRange<Double>? {
        estimate(
            entries.map {
                Pair(
                    errorsBefore: 0, wordsBefore: $0.referenceWordCount, errorsAfter: $0.errors,
                    wordsAfter: $0.referenceWordCount)
            })?.interval
    }

    static func quantile(_ sorted: [Double], _ fraction: Double) -> Double {
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    /// Acklam's rational approximation to the inverse normal distribution, accurate to about 1e-9.
    static func standardNormalQuantile(_ probability: Double) -> Double {
        let numeratorA = [
            -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
            1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00,
        ]
        let denominatorB = [
            -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
            6.680131188771972e+01, -1.328068155288572e+01,
        ]
        let numeratorC = [
            -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
            -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00,
        ]
        let denominatorD = [
            7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
            3.754408661907416e+00,
        ]
        func polynomial(_ coefficients: [Double], _ value: Double) -> Double {
            coefficients.reduce(0) { $0 * value + $1 }
        }
        let low = 0.02425
        if probability < low {
            let root = (-2 * log(probability)).squareRoot()
            return polynomial(numeratorC, root) / (polynomial(denominatorD, root) * root + 1)
        }
        if probability > 1 - low { return -standardNormalQuantile(1 - probability) }
        let centred = probability - 0.5
        let squared = centred * centred
        return polynomial(numeratorA, squared) * centred / (polynomial(denominatorB, squared) * squared + 1)
    }
}

/// A small deterministic generator, so the interval is a function of its inputs and the seed alone.
struct SplitMix {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
