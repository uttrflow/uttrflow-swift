// Measures how long the last piece is at key-up when a recording is cut the way the product cuts it.
private import Foundation
public import UttrflowCore

/// One spoken word and where it sits in its recording, in seconds.
public struct AlignedWord: Sendable, Equatable {
    public let word: String
    public let start: Double
    public let end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

/// The length of the piece left to decode at key-up, from word timings run through ``SpeechWindowing``.
public enum FinalPiece {
    /// The sample rate the rendered audio uses, the product's canonical rate.
    public static let sampleRate = AudioSamples.canonicalSampleRate

    /// Audio that is loud while a word is spoken and quiet between words, up to `keyUp` seconds.
    public static func render(_ words: [AlignedWord], until keyUp: Double) -> [Float] {
        let count = Swift.max(0, Int(keyUp * Double(sampleRate)))
        var samples = [Float](repeating: 0, count: count)
        var state: UInt32 = 0x9E37_79B9
        for index in 0..<count {
            state = state &* 1_664_525 &+ 1_013_904_223
            samples[index] = (Float(state >> 8) / Float(1 << 24) - 0.5) * 0.002
        }
        for word in words {
            let first = Swift.max(0, Int(word.start * Double(sampleRate)))
            let last = Swift.min(count, Int(word.end * Double(sampleRate)))
            guard first < last else { continue }
            for index in first..<last {
                samples[index] += 0.1 * Float(sin(Double(index) * 2 * Double.pi * 180 / Double(sampleRate)))
            }
        }
        return samples
    }

    /// Seconds of audio in the last piece when the key comes up at `keyUp`.
    public static func length(
        of words: [AlignedWord], keyUp: Double, windowing: SpeechWindowing = .standard
    ) -> Double {
        let samples = render(words, until: keyUp)
        guard let last = windowing.windows(in: samples, sampleRate: sampleRate).last else { return 0 }
        return Double(last.count) / Double(sampleRate)
    }

    /// Joins one speaker's utterances end to end, `gap` seconds apart, into one timeline.
    public static func concatenate(_ utterances: [[AlignedWord]], gap: Double) -> [AlignedWord] {
        var joined: [AlignedWord] = []
        var offset = 0.0
        for utterance in utterances {
            guard let first = utterance.first, let last = utterance.last else { continue }
            let shift = offset - first.start
            joined += utterance.map {
                AlignedWord(word: $0.word, start: $0.start + shift, end: $0.end + shift)
            }
            offset = last.end + shift + gap
        }
        return joined
    }

    /// The key-up point for a dictation of about `seconds`: the end of the last word that ends by then.
    public static func keyUp(in words: [AlignedWord], after seconds: Double) -> Double? {
        words.last { $0.end <= seconds }.map { $0.end + 0.2 }
    }

    /// The nearest-rank percentile of `values`, or `nil` when there are none.
    public static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[Swift.min(sorted.count - 1, Swift.max(0, rank))]
    }

    /// A deterministic synthetic speaker: words with short gaps, and a sentence pause drawn from `pauses`.
    public static func syntheticSpeaker(
        seconds: Double, pauses: ClosedRange<Double>, seed: UInt64
    ) -> [AlignedWord] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        var words: [AlignedWord] = []
        var time = 0.3
        var untilSentenceEnd = 8 + Int(next() * 9)
        while time < seconds {
            let end = time + 0.25 + next() * 0.2
            words.append(AlignedWord(word: "word", start: time, end: end))
            untilSentenceEnd -= 1
            if untilSentenceEnd == 0 {
                time = end + pauses.lowerBound + next() * (pauses.upperBound - pauses.lowerBound)
                untilSentenceEnd = 8 + Int(next() * 9)
            } else {
                time = end + 0.03 + next() * 0.09
            }
        }
        return words
    }
}
